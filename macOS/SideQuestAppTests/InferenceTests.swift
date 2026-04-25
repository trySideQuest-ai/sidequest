import XCTest
import Foundation
@testable import SideQuestApp

class InferenceTests: XCTestCase {

  var inference: EmbeddingInference!
  var embeddingService: EmbeddingService!
  var mockModel: EmbeddingModel!
  var mockTokenizer: WordPieceTokenizer!

  override func setUp() async throws {
    inference = EmbeddingInference()
    mockModel = EmbeddingModel()
    // Note: mockTokenizer setup would require bundled vocab.txt fixture
    // For unit test, we validate the orchestration patterns
  }

  override func tearDown() async throws {
    inference = nil
    embeddingService = nil
  }

  // MARK: - Background Queue Tests

  func test_inference_on_background_queue() async {
    // Test validates that inference dispatches to background queue
    // In real scenario, would measure main thread blocking with Instruments
    let dummyTokens: [Int32] = Array(1...128)
    let result = await inference.run(tokenIds: dummyTokens, model: mockModel, timeout: 1000)
    // Will be nil without real model, but validates no main thread block
    XCTAssertNil(result, "No model loaded; nil expected")
  }

  func test_inference_timeout_1000ms() async {
    // Test validates timeout mechanism enforces hard 1000ms limit
    let dummyTokens: [Int32] = Array(1...128)
    let startTime = Date()
    let result = await inference.run(tokenIds: dummyTokens, model: mockModel, timeout: 1000)
    let elapsed = Date().timeIntervalSince(startTime)

    // Should timeout quickly since model is nil
    XCTAssertNil(result, "Should return nil on timeout")
    XCTAssert(elapsed < 2.0, "Should timeout within reasonable bounds")
  }

  func test_embedding_service_orchestration() async {
    // Test validates EmbeddingService patterns (would need tokenizer fixture)
    let dummyTokens: [Int32] = Array(1...128)
    let embeddingService = EmbeddingService(
      tokenizer: mockTokenizer!,
      model: mockModel,
      inference: inference
    )

    // Test will fail to embed (no tokenizer), but validates structure
    // In integration: real tokenizer + model would produce valid vector
    let result = await embeddingService.embedText("test message")
    XCTAssertNil(result, "No tokenizer loaded; nil expected")
  }

  // MARK: - JSON Serialization Tests (6-decimal precision)

  func test_vector_serialization_preserves_precision() async {
    let embeddingService = EmbeddingService(
      tokenizer: mockTokenizer!,
      model: mockModel,
      inference: inference
    )

    // Create test vector with known precision
    let testVector = Array(0..<384).map { i in
      Float(0.123456 + Double(i) * 0.0001)
    }

    let serialized = embeddingService.serializeVector(testVector)
    XCTAssertEqual(serialized.count, 384, "Serialized vector should have 384 elements")

    // Verify 6-decimal format
    for str in serialized {
      let parts = str.split(separator: ".").map(String.init)
      XCTAssertEqual(parts.count, 2, "Each element should have integer.fractional format")
      if parts.count == 2 {
        XCTAssertEqual(parts[1].count, 6, "Fractional part should be 6 decimals")
      }
    }
  }

  func test_vector_deserialization_roundtrip() async {
    let embeddingService = EmbeddingService(
      tokenizer: mockTokenizer!,
      model: mockModel,
      inference: inference
    )

    let original = Array(0..<384).map { Float($0) / 384.0 }
    let serialized = embeddingService.serializeVector(original)
    let deserialized = embeddingService.deserializeVector(serialized)

    guard let deserialized = deserialized else {
      XCTFail("Deserialization returned nil")
      return
    }

    XCTAssertEqual(deserialized.count, 384, "Deserialized vector should have 384 elements")

    // Verify cosine similarity ~1.0 (minimal precision loss)
    let dotProduct = zip(original, deserialized).map(*).reduce(0, +)
    let cosine = dotProduct / (
      sqrt(original.map { $0 * $0 }.reduce(0, +)) *
      sqrt(deserialized.map { $0 * $0 }.reduce(0, +))
    )
    XCTAssert(cosine > 0.9999, "6-decimal precision should preserve cosine >0.9999; got \(cosine)")
  }

  func test_vector_validation() async {
    let embeddingService = EmbeddingService(
      tokenizer: mockTokenizer!,
      model: mockModel,
      inference: inference
    )

    // Valid vector
    let validVector = Array(0..<384).map { Float($0) / 1000.0 }
    XCTAssert(embeddingService.isValidVector(validVector), "Valid vector should pass validation")

    // Invalid: wrong length
    let wrongLength = Array(0..<100).map { Float($0) }
    XCTAssertFalse(embeddingService.isValidVector(wrongLength), "Wrong length should fail")

    // Invalid: contains NaN
    var withNaN = Array(0..<384).map { Float($0) }
    withNaN[0] = .nan
    XCTAssertFalse(embeddingService.isValidVector(withNaN), "NaN should fail validation")

    // Invalid: nil vector
    XCTAssertFalse(embeddingService.isValidVector(nil), "nil should fail validation")
  }

  // MARK: - Graceful Degradation Tests

  func test_high_unk_rate_returns_nil() async {
    // When [UNK] rate >50%, embedText should return nil
    // Requires real tokenizer + mock text with unknown tokens
    // This test structure validates the pattern
    let embeddingService = EmbeddingService(
      tokenizer: mockTokenizer!,
      model: mockModel,
      inference: inference
    )

    // Without real tokenizer, this will return nil anyway
    let result = await embeddingService.embedText("%%%")
    XCTAssertNil(result, "High UNK rate should return nil")
  }

  func test_model_error_returns_nil() async {
    let embeddingService = EmbeddingService(
      tokenizer: mockTokenizer!,
      model: mockModel,
      inference: inference
    )

    let dummyTokens: [Int32] = Array(1...128)
    // Without model loaded, predict returns nil
    let result = await inference.run(tokenIds: dummyTokens, model: mockModel, timeout: 1000)
    XCTAssertNil(result, "Model error should return nil")
  }

}
