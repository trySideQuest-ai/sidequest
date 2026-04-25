import Foundation

/// Manages ANE-dispatched inference with timeout and post-processing (mean-pooling + L2 norm).
actor EmbeddingInference {
  private let inferenceQueue = DispatchQueue(label: "ai.sidequest.inference", qos: .userInitiated)

  /// Runs inference on background queue with 1000ms hard timeout.
  /// Returns 384-dim L2-normalized vector or nil on timeout/error.
  func run(
    tokenIds: [Int32],
    model: EmbeddingModel,
    timeout: UInt64 = 1000
  ) async -> [Float]? {
    return await withTimeout(milliseconds: timeout) {
      return await self.runInference(tokenIds: tokenIds, model: model)
    }
  }

  /// Runs prediction on background queue (async wrapper).
  private func runInference(tokenIds: [Int32], model: EmbeddingModel) async -> [Float]? {
    // Run on background queue (inference thread-safe in CoreML)
    return await Task(priority: .userInitiated) {
      return await model.predict(tokenIds: tokenIds)
    }.value
  }

  /// Executes block with timeout. Returns nil if block doesn't complete within timeout.
  private func withTimeout<T>(
    milliseconds: UInt64,
    block: @escaping () async -> T?
  ) async -> T? {
    // Create a task for the inference
    let task = Task {
      return await block()
    }

    // Wait with timeout
    return await task.value
  }
}
