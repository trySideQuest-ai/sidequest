import Foundation
import CryptoKit

/// BERT WordPiece tokenizer for MiniLM L6 v2 embeddings.
/// Converts raw text to fixed-length token sequences for neural network inference.
/// Validates bundled vocabulary file via SHA256 hash at initialization.
class WordPieceTokenizer {
  private let vocabDict: [String: Int]
  private let unkToken = "[UNK]"
  private let clsToken = "[CLS]"
  private let sepToken = "[SEP]"
  private let padToken = "[PAD]"
  private let maxTokens = 128

  // Token IDs (from BERT base vocab)
  private let clsId: Int = 1
  private let sepId: Int = 102
  private let padId: Int = 0
  private var unkId: Int = 100  // Default; will be looked up from vocab

  /// Initializes tokenizer from a vocabulary file.
  /// - Parameters:
  ///   - bundleVocabPath: Path to vocab.txt
  ///   - expectedSHA256: SHA256 of vocab.txt for integrity validation. Pass nil
  ///     to skip validation — used when the source has already been verified
  ///     upstream (e.g. vocab arrived inside a tarball whose tarball-level
  ///     SHA256 was checked in EmbeddingModel.fetchFromS3).
  /// - Throws: NSError if vocab file cannot be read, or if a non-nil
  ///   expectedSHA256 mismatches.
  init(bundleVocabPath: String, expectedSHA256: String? = nil) throws {
    // Read vocab file
    let vocabContent = try String(contentsOfFile: bundleVocabPath, encoding: .utf8)

    if let expectedSHA256 = expectedSHA256 {
      let data = vocabContent.data(using: .utf8) ?? Data()
      let digest = SHA256.hash(data: data)
      let computedHash = digest.map { String(format: "%02x", $0) }.joined()

      guard computedHash == expectedSHA256 else {
        ErrorHandler.logInfo("Vocab SHA256 mismatch: expected \(expectedSHA256), got \(computedHash)")
        throw NSError(domain: "WordPieceTokenizer", code: 1, userInfo: [
          NSLocalizedDescriptionKey: "Vocabulary SHA256 validation failed"
        ])
      }
    }

    // Parse vocab.txt: one word per line, index = line number
    var vocab = [String: Int]()
    var lineNumber = 0
    for line in vocabContent.split(separator: "\n", omittingEmptySubsequences: false) {
      let word = String(line).trimmingCharacters(in: .whitespaces)
      if !word.isEmpty {
        vocab[word] = lineNumber
      }
      lineNumber += 1
    }

    self.vocabDict = vocab

    // Look up [UNK] token ID
    if let unkTokenId = vocab[unkToken] {
      self.unkId = unkTokenId
    }

    ErrorHandler.logInfo("WordPieceTokenizer initialized: \(vocab.count) tokens")
  }

  /// Tokenizes text into fixed-length token sequence.
  /// - Parameters:
  ///   - text: Raw text to tokenize (e.g., user message or assistant response)
  ///   - maxLen: Maximum token sequence length (default 128 for MiniLM)
  /// - Returns: Tuple of (tokenIds: fixed-length array, unkCount: number of [UNK] tokens)
  func tokenize(_ text: String, maxLen: Int = 128) -> (tokenIds: [Int], unkCount: Int) {
    var tokens: [Int] = []
    var unkCount = 0

    // Start with [CLS]
    tokens.append(clsId)

    // Process text: split by whitespace, then apply greedy longest-match
    let words = text.lowercased().split(separator: " ", omittingEmptySubsequences: true)

    for word in words {
      if tokens.count >= maxLen - 1 { break }  // Reserve one for [SEP]

      var pos = 0
      while pos < word.count {
        var end = word.count
        var found = false

        // Greedy longest-match: try to match from pos to end
        while end > pos {
          let wordStart = word.index(word.startIndex, offsetBy: pos)
          let wordEnd = word.index(word.startIndex, offsetBy: end)
          let subword = String(word[wordStart..<wordEnd])

          // Add ## prefix for subwords (not initial)
          let lookup = pos == 0 ? subword : "##" + subword

          if let tokenId = vocabDict[lookup] {
            tokens.append(tokenId)
            found = true
            pos = end
            break
          }

          end -= 1
        }

        if !found {
          // No match: emit [UNK]
          tokens.append(unkId)
          unkCount += 1
          pos += 1
        }
      }
    }

    // Add [SEP] (but don't exceed maxLen)
    if tokens.count < maxLen {
      tokens.append(sepId)
    }

    // Pad to maxLen with [PAD]
    while tokens.count < maxLen {
      tokens.append(padId)
    }

    // Truncate if needed (shouldn't happen with loop above, but defensive)
    tokens = Array(tokens.prefix(maxLen))

    return (tokenIds: tokens, unkCount: unkCount)
  }

  /// Computes [UNK] token rate for a token sequence.
  /// - Parameter tokenIds: Token IDs from tokenize()
  /// - Returns: Proportion of [UNK] tokens (0.0 to 1.0)
  func unkRate(tokenIds: [Int]) -> Double {
    guard !tokenIds.isEmpty else { return 0.0 }
    let unkTokenCount = tokenIds.filter { $0 == unkId }.count
    // Exclude [CLS] and [SEP] from denominator (structural tokens)
    let contentTokens = max(1, tokenIds.count - 2)
    return Double(unkTokenCount) / Double(contentTokens)
  }
}
