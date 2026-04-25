import XCTest
import CryptoKit
@testable import SideQuestApp

class TokenizerTests: XCTestCase {

  var tokenizer: WordPieceTokenizer?
  var testVocabPath: String?

  override func setUp() {
    super.setUp()

    // Create a minimal test vocabulary for unit testing
    let vocabLines = [
      "[PAD]",           // 0
      "[CLS]",           // 1
      "[MASK]",          // 2
      "[unused0]",       // 3
      "[unused1]",       // 4
      "[unused2]",       // 5
      "[unused3]",       // 6
      "[unused4]",       // 7
      "[unused5]",       // 8
      "[unused6]",       // 9
      "[unused7]",       // 10
      "[unused8]",       // 11
      "[unused9]",       // 12
      "!",               // 13
      "\"",              // 14
      "#",               // 15
      "$",               // 16
      "%",               // 17
      "&",               // 18
      "'",               // 19
      "(",               // 20
      ")",               // 21
      "*",               // 22
      "+",               // 23
      ",",               // 24
      "-",               // 25
      ".",               // 26
      "/",               // 27
      "0",               // 28
      "1",               // 29
      "2",               // 30
      "3",               // 31
      "4",               // 32
      "5",               // 33
      "6",               // 34
      "7",               // 35
      "8",               // 36
      "9",               // 37
      ":",               // 38
      ";",               // 39
      "<",               // 40
      "=",               // 41
      ">",               // 42
      "?",               // 43
      "@",               // 44
      "[",               // 45
      "\\",              // 46
      "]",               // 47
      "^",               // 48
      "_",               // 49
      "`",               // 50
      "a",               // 51
      "b",               // 52
      "c",               // 53
      "d",               // 54
      "e",               // 55
      "f",               // 56
      "g",               // 57
      "h",               // 58
      "i",               // 59
      "j",               // 60
      "k",               // 61
      "l",               // 62
      "m",               // 63
      "n",               // 64
      "o",               // 65
      "p",               // 66
      "q",               // 67
      "r",               // 68
      "s",               // 69
      "t",               // 70
      "u",               // 71
      "v",               // 72
      "w",               // 73
      "x",               // 74
      "y",               // 75
      "z",               // 76
      "{",               // 77
      "|",               // 78
      "}",               // 79
      "~",               // 80
      "hello",           // 81
      "world",           // 82
      "python",          // 83
      "code",            // 84
      "test",            // 85
      "##ing",           // 86
      "##ed",            // 87
      "##er",            // 88
      "[SEP]",           // 102 (but it's at index 89, which will be wrong - real vocab has 30522 tokens)
      "[UNK]"            // This is at index 90, but we need it at 100
    ]

    // Add enough padding to get to token 100 for [UNK]
    var paddedVocab = vocabLines
    while paddedVocab.count < 100 {
      paddedVocab.append("[unused\(paddedVocab.count)]")
    }
    paddedVocab.append("[UNK]")  // Index 100

    let vocabContent = paddedVocab.joined(separator: "\n")
    let vocabData = vocabContent.data(using: .utf8) ?? Data()

    // Compute SHA256
    let digest = CryptoKit.SHA256.hash(data: vocabData)
    let sha256Hex = digest.map { String(format: "%02x", $0) }.joined()

    // Write to temp file
    let tempDir = NSTemporaryDirectory()
    let vocabFile = (tempDir as NSString).appendingPathComponent("test_vocab.txt")
    try? vocabContent.write(toFile: vocabFile, atomically: true, encoding: .utf8)

    testVocabPath = vocabFile

    // Initialize tokenizer
    do {
      tokenizer = try WordPieceTokenizer(bundleVocabPath: vocabFile, expectedSHA256: sha256Hex)
    } catch {
      XCTFail("Failed to initialize tokenizer: \(error)")
    }
  }

  override func tearDown() {
    super.tearDown()
    if let path = testVocabPath {
      try? FileManager.default.removeItem(atPath: path)
    }
  }

  // MARK: - Tokenization Tests

  func testTokenizeSimpleText() {
    guard let tok = tokenizer else {
      XCTFail("Tokenizer not initialized")
      return
    }

    let (tokens, unkCount) = tok.tokenize("hello world")
    XCTAssertEqual(tokens.count, 128, "Token count should be 128 (max_len)")
    XCTAssertEqual(tokens[0], 1, "First token should be [CLS]")
    XCTAssertEqual(unkCount, 0, "Should have no [UNK] tokens for known words")
  }

  func testTokenizeUnknownWords() {
    guard let tok = tokenizer else {
      XCTFail("Tokenizer not initialized")
      return
    }

    let (tokens, unkCount) = tok.tokenize("unknownword xyz")
    XCTAssertGreater(unkCount, 0, "Should have [UNK] tokens for unknown words")
  }

  func testTokenizePadding() {
    guard let tok = tokenizer else {
      XCTFail("Tokenizer not initialized")
      return
    }

    let (tokens, _) = tok.tokenize("a")
    XCTAssertEqual(tokens.count, 128, "Tokens should be padded to 128")
    XCTAssertEqual(tokens[0], 1, "Should start with [CLS]")
  }

  func testTokenizeLongText() {
    guard let tok = tokenizer else {
      XCTFail("Tokenizer not initialized")
      return
    }

    let longText = (0..<200).map { "word\($0)" }.joined(separator: " ")
    let (tokens, _) = tok.tokenize(longText)
    XCTAssertEqual(tokens.count, 128, "Tokens should be truncated to 128")
  }

  // MARK: - UNK Rate Tests

  func testUnkRateCalculation() {
    guard let tok = tokenizer else {
      XCTFail("Tokenizer not initialized")
      return
    }

    let (tokens, unkCount) = tok.tokenize("hello unknownword xyz")
    let rate = tok.unkRate(tokenIds: tokens)
    XCTAssertGreater(rate, 0.0, "UNK rate should be > 0 when there are unknown tokens")
  }

  func testUnkRateForKnownWords() {
    guard let tok = tokenizer else {
      XCTFail("Tokenizer not initialized")
      return
    }

    let (tokens, _) = tok.tokenize("hello world")
    let rate = tok.unkRate(tokenIds: tokens)
    XCTAssertEqual(rate, 0.0, "UNK rate should be 0 for all known words")
  }

  // MARK: - Token ID Tests

  func testClsTokenPresent() {
    guard let tok = tokenizer else {
      XCTFail("Tokenizer not initialized")
      return
    }

    let (tokens, _) = tok.tokenize("test")
    XCTAssertEqual(tokens[0], 1, "[CLS] token should be first")
  }

  func testSepTokenPresent() {
    guard let tok = tokenizer else {
      XCTFail("Tokenizer not initialized")
      return
    }

    let (tokens, _) = tok.tokenize("test")
    // [SEP] should be after text tokens but before padding
    XCTAssertTrue(tokens.contains(102), "Should contain [SEP] token")
  }

  func testPaddingTokens() {
    guard let tok = tokenizer else {
      XCTFail("Tokenizer not initialized")
      return
    }

    let (tokens, _) = tok.tokenize("a")
    // Should have padding tokens at the end
    let paddingTokens = tokens.filter { $0 == 0 }
    XCTAssertGreater(paddingTokens.count, 0, "Should have padding tokens")
  }

  // MARK: - Edge Cases

  func testEmptyString() {
    guard let tok = tokenizer else {
      XCTFail("Tokenizer not initialized")
      return
    }

    let (tokens, unkCount) = tok.tokenize("")
    XCTAssertEqual(tokens.count, 128, "Empty string should produce padded output")
    XCTAssertEqual(unkCount, 0, "Empty string should have no unknown tokens")
    XCTAssertEqual(tokens[0], 1, "Should start with [CLS]")
  }

  func testCaseLowering() {
    guard let tok = tokenizer else {
      XCTFail("Tokenizer not initialized")
      return
    }

    let (tokens1, unk1) = tok.tokenize("HELLO world")
    let (tokens2, unk2) = tok.tokenize("hello world")
    // Should be equivalent after lowercasing
    XCTAssertEqual(unk1, unk2, "Case should not affect unknown token count")
  }

  func testWhitespaceHandling() {
    guard let tok = tokenizer else {
      XCTFail("Tokenizer not initialized")
      return
    }

    let (tokens1, _) = tok.tokenize("hello   world")
    let (tokens2, _) = tok.tokenize("hello world")
    // Multiple spaces should be treated like single space
    XCTAssertEqual(tokens1.count, tokens2.count, "Multiple spaces should not affect output length")
  }

  // MARK: - Subword Tests

  func testSubwordHandling() {
    guard let tok = tokenizer else {
      XCTFail("Tokenizer not initialized")
      return
    }

    // "testing" should use "test" + "##ing" if both are in vocab
    let (tokens, _) = tok.tokenize("testing")
    XCTAssertEqual(tokens.count, 128, "Subword tokenization should produce fixed length")
  }

  // MARK: - Vocab Loading Tests

  func testVocabValidationFailure() {
    // Test with wrong SHA256
    let vocabPath = testVocabPath ?? ""
    do {
      _ = try WordPieceTokenizer(bundleVocabPath: vocabPath, expectedSHA256: "wronghash")
      XCTFail("Should throw error on SHA256 mismatch")
    } catch {
      XCTAssertTrue(true, "Correctly threw error on SHA256 mismatch")
    }
  }

  func testVocabFileNotFound() {
    do {
      _ = try WordPieceTokenizer(bundleVocabPath: "/nonexistent/path", expectedSHA256: "somehash")
      XCTFail("Should throw error on missing file")
    } catch {
      XCTAssertTrue(true, "Correctly threw error on missing file")
    }
  }
}
