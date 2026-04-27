import Foundation
import CoreML
import CryptoKit

/// Manages CoreML model loading for EmbeddingGemma-300M inference.
/// Handles S3 downloads with exponential backoff retry and SHA256 verification.
/// Extends v2.1 EmbeddingModel pattern for model-agnostic interface.
actor EmbeddingGemmaModel {
  private var mlModel: MLModel?
  private let modelCachePath: String
  private let modelVersion = "1.0.0"
  private let modelName = "embeddinggemma-300m"

  init() {
    let home = FileManager.default.homeDirectoryForCurrentUser
    self.modelCachePath = home.appendingPathComponent(".sidequest/models").path
  }

  /// Filesystem path of the .mlmodelc directory shipped inside the tarball.
  nonisolated var modelDirPath: String {
    return "\(modelCachePath)/\(modelName)-\(modelVersion).mlmodelc"
  }

  /// Filesystem path of the SentencePiece tokenizer.model file.
  nonisolated var tokenizerPath: String {
    return "\(modelCachePath)/\(modelName)-\(modelVersion)-tokenizer.model"
  }

  /// Attempts to load model from cache; fetches from S3 if not cached.
  /// Returns true on success, false on persistent failure.
  func loadOrFetch() async -> Bool {
    let loadStartTime = Date()

    // Try cached first
    if let cached = tryLoadCached() {
      self.mlModel = cached
      let warmLoadDuration = Date().timeIntervalSince(loadStartTime) * 1000
      EmbeddingModelMetrics.shared.recordLatency(stage: "model_load_warm", durationMs: warmLoadDuration)
      return true
    }

    // Fetch from S3 if not cached
    let fetchStartTime = Date()
    if await fetchFromS3() {
      let fetchDuration = Date().timeIntervalSince(fetchStartTime) * 1000
      EmbeddingModelMetrics.shared.recordLatency(stage: "first_launch_download", durationMs: fetchDuration)

      let extractStartTime = Date()
      if let model = tryLoadCached() {
        let extractDuration = Date().timeIntervalSince(extractStartTime) * 1000
        EmbeddingModelMetrics.shared.recordLatency(stage: "first_launch_extract", durationMs: extractDuration)

        let modelLoadStartTime = Date()
        self.mlModel = model
        let modelLoadDuration = Date().timeIntervalSince(modelLoadStartTime) * 1000
        EmbeddingModelMetrics.shared.recordLatency(stage: "first_launch_model_load", durationMs: modelLoadDuration)

        let totalDuration = Date().timeIntervalSince(loadStartTime) * 1000
        EmbeddingModelMetrics.shared.recordLatency(stage: "first_launch_total", durationMs: totalDuration)
        return true
      }
    }

    // Fallback: no model available
    return false
  }

  /// Performs inference on tokenized input.
  /// Input: token IDs from SentencePieceTokenizer
  /// Output: 768-dimensional embedding vector (L2-normalized fp16 internally)
  ///
  /// Bundle is built with fixed shape (1, 128). Pad shorter input with token id 0,
  /// truncate longer input. attention_mask is fp16 [1, 128] — 1.0 for real tokens,
  /// 0.0 for pad positions — built from the original token count before padding.
  func inference(tokenIds: [Int]) throws -> [Float]? {
    guard let model = mlModel else {
      ErrorHandler.logInfo("EmbeddingGemmaModel: model not loaded")
      return nil
    }

    let seqLen = 128
    let realCount = min(tokenIds.count, seqLen)

    do {
      let idsArray = try MLMultiArray(shape: [1, NSNumber(value: seqLen)], dataType: .int32)
      let maskArray = try MLMultiArray(shape: [1, NSNumber(value: seqLen)], dataType: .float16)
      for i in 0..<seqLen {
        if i < realCount {
          idsArray[i] = NSNumber(value: Int32(tokenIds[i]))
          maskArray[i] = NSNumber(value: Float(1.0))
        } else {
          idsArray[i] = NSNumber(value: Int32(0))
          maskArray[i] = NSNumber(value: Float(0.0))
        }
      }

      let input = EmbeddingGemmaModelInput(input_ids: idsArray, attention_mask: maskArray)
      let output = try model.prediction(from: input) as! EmbeddingGemmaModelOutput

      let embedding = output.embedding
      var result: [Float] = []
      result.reserveCapacity(embedding.count)
      for i in 0..<embedding.count {
        result.append(Float(truncating: embedding[i]))
      }
      return result
    } catch {
      ErrorHandler.logInfo("EmbeddingGemmaModel inference error: \(error)")
      return nil
    }
  }

  /// Attempts to load model from local cache directory.
  /// Validates the .mlmodelc directory exists.
  private func tryLoadCached() -> MLModel? {
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: modelDirPath, isDirectory: &isDir),
          isDir.boolValue else {
      return nil
    }

    do {
      let url = URL(fileURLWithPath: modelDirPath)
      let config = MLModelConfiguration()
      // Prefer Apple Neural Engine for M-series Macs; CPU fallback
      config.computeUnits = .cpuAndNeuralEngine
      config.allowLowPrecisionAccumulationOnGPU = false

      let model = try MLModel(contentsOf: url, configuration: config)
      ErrorHandler.logInfo("Loaded CoreML model from cache: \(modelDirPath)")
      return model
    } catch {
      ErrorHandler.logInfo("Failed to load cached model: \(error)")
      return nil
    }
  }

  /// Fetches model from S3 with exponential backoff retry.
  /// 3 attempts with 1s, 2s, 4s delays. 30s total timeout.
  /// Verifies SHA256 before caching. Returns true on success.
  private func fetchFromS3() async -> Bool {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let candidatePaths = [
      home.appendingPathComponent(".sidequest/remote-config.json").path,
      home.appendingPathComponent(".sidequest/config.json").path
    ]

    var modelURL: URL?
    var expectedSHA256: String?

    for configPath in candidatePaths {
      guard let configData = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
            let json = try? JSONSerialization.jsonObject(with: configData) as? [String: Any],
            let urlString = json["model_url"] as? String,
            let sha256 = json["model_sha256"] as? String else {
        continue
      }
      modelURL = URL(string: urlString)
      expectedSHA256 = sha256
      break
    }

    guard let url = modelURL, let expectedSHA = expectedSHA256 else {
      ErrorHandler.logInfo("EmbeddingGemmaModel: No model_url or model_sha256 in config")
      return false
    }

    // Download with retry (1s, 2s, 4s backoff)
    let deadline = Date().addingTimeInterval(30.0)
    for attempt in 0..<3 {
      guard Date() < deadline else {
        ErrorHandler.logInfo("EmbeddingGemmaModel: Fetch timeout exceeded")
        return false
      }

      let backoff = pow(2.0, Double(attempt))
      if attempt > 0 {
        try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
      }

      do {
        let (data, _) = try await URLSession.shared.data(from: url)
        let actualSHA = SHA256.hash(data: data)
        let computedHash = actualSHA.map { String(format: "%02x", $0) }.joined()

        guard computedHash == expectedSHA else {
          ErrorHandler.logInfo("EmbeddingGemmaModel: SHA256 mismatch")
          continue
        }

        // Atomic extract to cache
        if await atomicExtractTarball(data, to: modelCachePath) {
          return true
        }
      } catch {
        ErrorHandler.logInfo("EmbeddingGemmaModel: Download attempt \(attempt + 1) failed: \(error)")
        continue
      }
    }

    return false
  }

  /// Atomically extracts tarball to cache directory.
  private func atomicExtractTarball(_ data: Data, to destination: String) async -> Bool {
    let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("sidequest-\(UUID().uuidString)")

    do {
      try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

      // Write tarball to temp location
      let tarPath = tempDir.appendingPathComponent("model.tar.gz")
      try data.write(to: tarPath)

      // Extract tarball (system tar command)
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
      process.arguments = ["-xzf", tarPath.path, "-C", tempDir.path]
      try process.run()
      process.waitUntilExit()

      // Move extracted content to final location
      let destURL = URL(fileURLWithPath: destination)
      try? FileManager.default.createDirectory(at: destURL, withIntermediateDirectories: true)

      // Rename atomic (temp → final)
      try FileManager.default.replaceItemAt(destURL, withItemAt: tempDir)
      ErrorHandler.logInfo("EmbeddingGemmaModel: Tarball extracted atomically to \(destination)")
      return true
    } catch {
      // Cleanup temp on failure
      try? FileManager.default.removeItem(at: tempDir)
      ErrorHandler.logInfo("EmbeddingGemmaModel: Atomic extract failed: \(error)")
      return false
    }
  }
}

// MARK: - CoreML Generated Types (stub placeholders)

/// Expected CoreML model input structure.
/// Real type generated by coremltools during model compilation.
class EmbeddingGemmaModelInput: NSObject, MLFeatureProvider {
  let input_ids: MLMultiArray
  let attention_mask: MLMultiArray

  init(input_ids: MLMultiArray, attention_mask: MLMultiArray) {
    self.input_ids = input_ids
    self.attention_mask = attention_mask
    super.init()
  }

  var featureNames: Set<String> {
    return Set(arrayLiteral: "input_ids", "attention_mask")
  }

  func featureValue(for featureName: String) -> MLFeatureValue? {
    switch featureName {
    case "input_ids":
      return MLFeatureValue(multiArray: input_ids)
    case "attention_mask":
      return MLFeatureValue(multiArray: attention_mask)
    default:
      return nil
    }
  }
}

/// Expected CoreML model output structure.
class EmbeddingGemmaModelOutput: NSObject, MLFeatureProvider {
  let embedding: MLMultiArray

  init(embedding: MLMultiArray) {
    self.embedding = embedding
  }

  var featureNames: Set<String> {
    return Set(arrayLiteral: "embedding")
  }

  func featureValue(for featureName: String) -> MLFeatureValue? {
    switch featureName {
    case "embedding":
      return MLFeatureValue(multiArray: embedding)
    default:
      return nil
    }
  }
}
