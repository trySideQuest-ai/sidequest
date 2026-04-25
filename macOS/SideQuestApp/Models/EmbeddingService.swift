import Foundation

/// Orchestrates full embedding pipeline: tokenization → inference → serialization.
/// Handles graceful degradation for all failure modes (UNK rate, timeout, model error).
actor EmbeddingService {
  private let tokenizer: WordPieceTokenizer
  private let model: EmbeddingModel
  private let inference: EmbeddingInference

  init(tokenizer: WordPieceTokenizer, model: EmbeddingModel, inference: EmbeddingInference) {
    self.tokenizer = tokenizer
    self.model = model
    self.inference = inference
  }

  /// Embeds text into 384-dim L2-normalized vector.
  /// Returns nil on tokenization failure (>50% UNK), timeout, or model error.
  func embedText(_ text: String) async -> [Float]? {
    // Tokenize
    let (tokenIds, unkCount) = tokenizer.tokenize(text)
    let unkRate = tokenIds.count > 0 ? Double(unkCount) / Double(tokenIds.count) : 0

    // Check UNK rate threshold
    if unkRate > 0.5 {
      ErrorHandler.logInfo("High [UNK] rate (\(String(format: "%.1f", unkRate * 100))%); input unrecognizable; returning null vector")
      return nil
    }

    if unkCount > 0 {
      ErrorHandler.logInfo("Tokenization: [UNK] rate \(String(format: "%.1f", unkRate * 100))% for input")
    }

    // Convert token IDs to Int32 and run inference with timeout
    let tokenIds32 = tokenIds.map { Int32($0) }
    let vector = await inference.run(tokenIds: tokenIds32, model: model, timeout: 1000)
    return vector
  }

  /// Serializes vector to JSON-safe string array at 6-decimal precision.
  /// Each element formatted as "%.6f" for consistent round-trip precision.
  nonisolated func serializeVector(_ vector: [Float]) -> [String] {
    return vector.map { String(format: "%.6f", $0) }
  }

  /// Deserializes string array back to float vector.
  /// Returns nil if any element fails to parse or array has wrong length.
  nonisolated func deserializeVector(_ strings: [String]) -> [Float]? {
    guard strings.count == 384 else {
      return nil
    }

    var vector = [Float]()
    for str in strings {
      guard let value = Float(str) else {
        return nil
      }
      vector.append(value)
    }
    return vector
  }

  /// Validates vector for finite values (no NaN/Inf) and correct dimension.
  nonisolated func isValidVector(_ vector: [Float]?) -> Bool {
    guard let v = vector, v.count == 384 else {
      return false
    }
    return v.allSatisfy { !$0.isNaN && !$0.isInfinite }
  }
}
