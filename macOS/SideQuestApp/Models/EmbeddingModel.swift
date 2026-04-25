import Foundation
import CoreML
import CryptoKit

/// Manages CoreML model loading and caching for embedding inference.
/// Handles S3 downloads with exponential backoff retry and SHA256 verification.
actor EmbeddingModel {
  private var mlModel: MLModel?
  private let modelCachePath: String
  private let modelVersion = "2.1.0"

  init() {
    let home = FileManager.default.homeDirectoryForCurrentUser
    self.modelCachePath = home.appendingPathComponent(".sidequest/models").path
  }

  /// Filesystem path of the .mlmodelc directory shipped inside the tarball.
  /// AppDelegate reads this to know where the compiled model lives after fetch.
  nonisolated var modelDirPath: String {
    return "\(modelCachePath)/minilm-l6-v2-\(modelVersion).mlmodelc"
  }

  /// Filesystem path of the BERT vocab.txt shipped alongside the model in the
  /// same tarball. WordPieceTokenizer is initialized from this path after
  /// loadOrFetch() succeeds — pairing keeps vocab version-locked to the model.
  nonisolated var vocabPath: String {
    return "\(modelCachePath)/minilm-l6-v2-\(modelVersion)-vocab.txt"
  }

  /// Attempts to load model from cache; fetches from S3 if not cached.
  /// Returns true on success, false on persistent failure.
  func loadOrFetch() async -> Bool {
    // Try cached first
    if let cached = tryLoadCached() {
      self.mlModel = cached
      return true
    }

    // Fetch from S3 if not cached
    if await fetchFromS3() {
      if let model = tryLoadCached() {
        self.mlModel = model
        return true
      }
    }

    // Fallback: no model available
    return false
  }

  /// Attempts to load model from local cache directory.
  /// Validates the .mlmodelc directory exists and loads via MLModel API with
  /// ANE configuration. .mlmodelc is a directory, not a file — use
  /// isDirectory checking, not fileExists alone.
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
  /// 3 attempts with 1s, 2s, 4s delays. 30s timeout per attempt.
  /// Verifies SHA256 before caching. Returns true on success.
  private func fetchFromS3() async -> Bool {
    // Read config.json for S3 URL and expected SHA256
    let configPath = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".sidequest/config.json").path

    var modelURL: URL?
    var expectedSHA256: String?

    if let configData = try? Data(contentsOf: URL(fileURLWithPath: configPath)) {
      if let json = try? JSONSerialization.jsonObject(with: configData) as? [String: Any],
         let urlString = json["model_url"] as? String,
         let sha256 = json["model_sha256"] as? String {
        modelURL = URL(string: urlString)
        expectedSHA256 = sha256
      }
    }

    guard let url = modelURL, let expectedHash = expectedSHA256 else {
      ErrorHandler.logInfo("Model URL or SHA256 missing from config.json")
      return false
    }

    // Ensure cache directory exists
    do {
      try FileManager.default.createDirectory(
        atPath: modelCachePath,
        withIntermediateDirectories: true
      )
    } catch {
      ErrorHandler.logInfo("Failed to create cache directory: \(error)")
      return false
    }

    // Retry loop: 3 attempts with exponential backoff (1s, 2s, 4s)
    for attempt in 0..<3 {
      let backoffSeconds = 1 << attempt  // 1, 2, 4 seconds
      let backoffNanos = UInt64(backoffSeconds) * 1_000_000_000

      if attempt > 0 {
        // Wait before retry (not on first attempt)
        try? await Task.sleep(nanoseconds: backoffNanos)
      }

      // Attempt download with 30s timeout
      do {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30.0

        let (data, response) = try await URLSession.shared.data(for: request)

        // Validate HTTP response
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
          ErrorHandler.logInfo("Model download failed: HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
          continue
        }

        // Verify SHA256 of the tarball before extraction. The tarball SHA256
        // covers both the .mlmodelc directory and vocab.txt atomically, so
        // there's no separate vocab integrity check needed downstream.
        let digest = SHA256.hash(data: data)
        let computedHash = digest.map { String(format: "%02x", $0) }.joined()

        guard computedHash == expectedHash else {
          ErrorHandler.logInfo("Model SHA256 mismatch: expected \(expectedHash), got \(computedHash)")
          continue
        }

        // S3 ships .tar.gz; .mlmodelc is a directory. Save tarball to disk
        // then shell out to /usr/bin/tar to extract into the cache dir.
        // After extraction the cache dir contains both the .mlmodelc dir
        // and the matching vocab.txt produced by build-coreml-model.sh.
        let tarPath = "\(modelCachePath)/minilm-l6-v2-\(modelVersion).mlmodelc.tar.gz"

        // Clean any prior partial state so extraction starts fresh.
        try? FileManager.default.removeItem(atPath: tarPath)
        try? FileManager.default.removeItem(atPath: modelDirPath)
        try? FileManager.default.removeItem(atPath: vocabPath)

        do {
          try data.write(to: URL(fileURLWithPath: tarPath))
        } catch {
          ErrorHandler.logInfo("Failed to write tarball to disk: \(error)")
          continue
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xzf", tarPath, "-C", modelCachePath]
        do {
          try process.run()
        } catch {
          ErrorHandler.logInfo("tar launch failed: \(error)")
          try? FileManager.default.removeItem(atPath: tarPath)
          continue
        }
        process.waitUntilExit()

        // Tarball is no longer needed once extracted — remove either way so
        // the cache dir doesn't accumulate copies across version bumps.
        try? FileManager.default.removeItem(atPath: tarPath)

        guard process.terminationStatus == 0 else {
          ErrorHandler.logInfo("tar extraction failed: status \(process.terminationStatus)")
          try? FileManager.default.removeItem(atPath: modelDirPath)
          try? FileManager.default.removeItem(atPath: vocabPath)
          continue
        }

        // Verify both expected artifacts landed where the loader + tokenizer
        // expect them. A tarball that extracted but lacks either file is a
        // packaging bug, not a transient failure — skip the retry loop.
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: modelDirPath, isDirectory: &isDir),
              isDir.boolValue,
              FileManager.default.fileExists(atPath: vocabPath) else {
          ErrorHandler.logInfo("Tarball missing expected contents (model dir or vocab.txt)")
          continue
        }

        ErrorHandler.logInfo("Downloaded + extracted model from S3 (attempt \(attempt + 1))")
        return true
      } catch URLError.timedOut {
        ErrorHandler.logInfo("Model download timeout (attempt \(attempt + 1))")
        continue
      } catch {
        ErrorHandler.logInfo("Model download error (attempt \(attempt + 1)): \(error)")
        continue
      }
    }

    ErrorHandler.logInfo("Model fetch failed after 3 attempts")
    return false
  }

  /// Runs inference on token input. Returns 384-dim output vector or nil on error.
  /// Caller responsible for timeout management via EmbeddingService.
  func predict(tokenIds: [Int32]) -> [Float]? {
    guard let model = mlModel else {
      return nil
    }

    do {
      // Create input MLMultiArray for token IDs
      // Input shape: [1, 128] for batch=1, seq_len=128
      let input = try MLMultiArray(
        shape: [1, 128],
        dataType: .int32
      )

      // Fill token IDs (pad with 0s if input shorter than 128)
      for i in 0..<128 {
        let tokenId: Int32 = i < tokenIds.count ? tokenIds[i] : 0
        input[i] = NSNumber(value: tokenId)
      }

      // Create input dictionary and run inference using MLDictionaryFeatureProvider
      let inputDict: [String: MLFeatureValue] = ["input_ids": MLFeatureValue(multiArray: input)]
      let inputProvider = try MLDictionaryFeatureProvider(dictionary: inputDict)
      let output = try model.prediction(from: inputProvider)

      // Extract embeddings from output
      // Expected output key: "embeddings" or similar (model-dependent)
      guard let embeddingsFeature = output.featureValue(for: "embeddings") else {
        ErrorHandler.logInfo("Model output missing 'embeddings' key")
        return nil
      }

      // Convert to multi-array and extract float values
      guard let embeddings = embeddingsFeature.multiArrayValue else {
        return nil
      }

      // Extract 384-dim vector (pooled output)
      var vector = [Float](repeating: 0, count: 384)
      for i in 0..<min(384, embeddings.count) {
        vector[i] = Float(truncating: embeddings[i] as NSNumber)
      }

      // L2 normalization
      let norm = sqrt(vector.reduce(0) { $0 + $1 * $1 })
      let normalizedVector = vector.map { $0 / (norm + 1e-6) }

      return normalizedVector
    } catch {
      ErrorHandler.logInfo("Inference failed: \(error)")
      return nil
    }
  }
}
