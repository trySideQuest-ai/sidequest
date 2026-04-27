import Foundation

struct EmbeddingLatencySnapshot {
  let timestamp: Date
  let stage: String  // "model_load_cold", "model_load_warm", "inference", "first_launch_download", "first_launch_extract", "first_launch_model_load", "first_launch_inference", "first_launch_total"
  let durationMs: Double
  let deviceModel: String  // "M1", "M2", "M3", or "unknown"
  let memoryMB: Int?  // optional peak memory during operation
}

class EmbeddingModelMetrics {
  static let shared = EmbeddingModelMetrics()

  private var snapshots: [EmbeddingLatencySnapshot] = []
  private let queue = DispatchQueue(label: "ai.sidequest.embedding-metrics")
  private let metricsFilePath: String

  init() {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let appSupportPath = home.appendingPathComponent("Library/Application Support/SideQuest")

    do {
      try FileManager.default.createDirectory(at: appSupportPath, withIntermediateDirectories: true)
    } catch {
      ErrorHandler.logInfo("Failed to create SideQuest app support directory: \(error)")
    }

    self.metricsFilePath = appSupportPath.appendingPathComponent("embedding-metrics.json").path
  }

  /// Record a single latency measurement
  func recordLatency(stage: String, durationMs: Double, memoryMB: Int? = nil) {
    let deviceModel = getDeviceModel()
    let snapshot = EmbeddingLatencySnapshot(
      timestamp: Date(),
      stage: stage,
      durationMs: durationMs,
      deviceModel: deviceModel,
      memoryMB: memoryMB
    )

    queue.async {
      self.snapshots.append(snapshot)
      ErrorHandler.logInfo("[EmbeddingMetrics] \(stage): \(String(format: "%.0f", durationMs))ms on \(deviceModel)")

      // Keep only recent snapshots (last 1000 to allow multiple runs)
      if self.snapshots.count > 1000 {
        self.snapshots.removeFirst(self.snapshots.count - 1000)
      }

      // Persist inline. We're already on `queue`, so going through
      // exportMetricsJSON()→getSessionMetrics() would re-enter queue.sync
      // and trip libdispatch's deadlock detector (BUG IN CLIENT OF
      // LIBDISPATCH: dispatch_sync called on queue already owned by
      // current thread). Compute the aggregates directly from snapshots
      // and write the file without re-locking.
      let aggregates = self.aggregatesLocked()
      self.writeAggregatesUnsafe(aggregates)
    }
  }

  /// Get aggregated metrics for the current session (EVAL-04/05 reporting).
  /// Public entry — locks the queue. Do NOT call from code already running
  /// on `queue`; use `aggregatesLocked()` for that path.
  func getSessionMetrics() -> [String: Any] {
    return queue.sync { aggregatesLocked() }
  }

  /// Compute aggregates from snapshots. CALLER MUST already be on `queue`.
  private func aggregatesLocked() -> [String: Any] {
    var aggregates: [String: Any] = [:]
    var stageMetrics: [String: [Double]] = [:]

    for snapshot in snapshots {
      if stageMetrics[snapshot.stage] == nil {
        stageMetrics[snapshot.stage] = []
      }
      stageMetrics[snapshot.stage]?.append(snapshot.durationMs)
    }

    for (stage, durations) in stageMetrics {
      let sorted = durations.sorted()
      let p50Index = Int(Double(sorted.count) * 0.50)
      let p99Index = Int(Double(sorted.count) * 0.99)

      let p50 = p50Index < sorted.count ? sorted[p50Index] : sorted.last ?? 0
      let p99 = p99Index < sorted.count ? sorted[p99Index] : sorted.last ?? 0
      let mean = durations.reduce(0, +) / Double(durations.count)

      aggregates[stage] = [
        "p50_ms": p50,
        "p99_ms": p99,
        "mean_ms": mean,
        "count": durations.count,
      ]
    }

    return aggregates
  }

  /// Export metrics to JSON string for analysis
  func exportMetricsJSON() -> String {
    let metrics = getSessionMetrics()
    do {
      let json = try JSONSerialization.data(withJSONObject: metrics, options: .prettyPrinted)
      return String(data: json, encoding: .utf8) ?? "{}"
    } catch {
      ErrorHandler.logInfo("Failed to serialize metrics to JSON: \(error)")
      return "{}"
    }
  }

  /// Write pre-computed aggregates to disk without re-locking. Used from
  /// within the queue.async block in recordLatency.
  private func writeAggregatesUnsafe(_ aggregates: [String: Any]) {
    do {
      let json = try JSONSerialization.data(withJSONObject: aggregates, options: .prettyPrinted)
      try json.write(to: URL(fileURLWithPath: metricsFilePath), options: .atomic)
    } catch {
      ErrorHandler.logInfo("Failed to persist metrics to disk: \(error)")
    }
  }

  /// Load persisted metrics from disk
  func loadPersistedMetrics() -> [String: Any]? {
    do {
      let data = try Data(contentsOf: URL(fileURLWithPath: metricsFilePath))
      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
      return json
    } catch {
      ErrorHandler.logInfo("Failed to load persisted metrics: \(error)")
      return nil
    }
  }

  /// Get device model name (M1, M2, M3, etc.)
  private func getDeviceModel() -> String {
    // Use sysctl to detect Mac model
    var size = 0
    sysctlbyname("hw.model", nil, &size, nil, 0)

    if size > 0 {
      var model = [CChar](repeating: 0, count: size)
      sysctlbyname("hw.model", &model, &size, nil, 0)
      let modelStr = String(cString: model)

      if modelStr.contains("MacBookPro18,1") || modelStr.contains("MacBookPro18,2") {
        return "M1_Pro"
      } else if modelStr.contains("MacBookPro18,3") || modelStr.contains("MacBookPro18,4") {
        return "M1_Max"
      } else if modelStr.contains("MacBookAir11,1") || modelStr.contains("MacBookAir13,1") {
        return "M2"
      } else if modelStr.contains("MacBookPro19,1") || modelStr.contains("MacBookPro19,2") {
        return "M2_Pro"
      } else if modelStr.contains("MacBookPro19,3") || modelStr.contains("MacBookPro19,4") {
        return "M2_Max"
      } else if modelStr.contains("MacBookPro20,1") || modelStr.contains("MacBookPro20,2") {
        return "M3"
      } else if modelStr.contains("MacBookPro20,3") || modelStr.contains("MacBookPro20,4") {
        return "M3_Pro"
      } else if modelStr.contains("MacBookPro20,5") || modelStr.contains("MacBookPro20,6") {
        return "M3_Max"
      }
    }

    // Fallback: use processor count heuristic
    return "M-series"
  }

  /// Compute percentiles (p50, p99) for a given stage
  func computePercentiles(for stage: String) -> [String: Double] {
    let metrics = getSessionMetrics()
    if let stageData = metrics[stage] as? [String: Any],
       let p50 = stageData["p50_ms"] as? Double,
       let p99 = stageData["p99_ms"] as? Double {
      return ["p50_ms": p50, "p99_ms": p99]
    }
    return [:]
  }
}
