import Foundation
import PDFKit

enum PDFExtraction {
  static func extract(_ data: Data) -> DocumentResult {
    guard data.count <= DocumentWorkerLimits.inputBytes else { return .init(status: .inputLimit) }
    guard let document = PDFDocument(data: data) else { return .init(status: .malformed) }
    guard !document.isEncrypted, !document.isLocked else { return .init(status: .encrypted) }
    guard document.pageCount > 0, document.pageCount <= DocumentWorkerLimits.pages else {
      return .init(status: .pageLimit)
    }
    var text = BoundedText()
    for index in 0..<document.pageCount {
      guard let pageText = document.page(at: index)?.string else {
        return .init(status: .unreadable)
      }
      guard text.append(pageText), text.append("\n") else { break }
    }
    return .init(status: .extracted, text: text.trimmed)
  }
}

/// Extracted text kept within both the character limit and the reply's encoded-size budget.
struct BoundedText {
  private static let worstCaseEscapeBytes = 6
  private static let escapedASCII: Set<Unicode.Scalar> = ["\"", "\\", "/"]

  private(set) var text = ""
  private var characters = 0, encodedBytes = 0

  var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

  /// Counts the bytes a scalar can occupy once JSON-encoded, assuming the longest escape.
  static func encodedBytes(of scalar: Unicode.Scalar) -> Int {
    guard scalar.isASCII else { return scalar.utf8.count }
    return scalar.value < 0x20 || escapedASCII.contains(scalar) ? worstCaseEscapeBytes : 1
  }

  static func encodedBytes(of character: Character) -> Int {
    character.unicodeScalars.reduce(0) { $0 + encodedBytes(of: $1) }
  }

  /// Appends whole characters until a limit is reached.
  /// - Returns: Whether all of `addition` fit.
  mutating func append(_ addition: some StringProtocol) -> Bool {
    for character in addition {
      let cost = Self.encodedBytes(of: character)
      guard characters < DocumentWorkerLimits.textCharacters,
        encodedBytes + cost <= DocumentWorkerLimits.textBytes
      else { return false }
      text.append(character)
      characters += 1
      encodedBytes += cost
    }
    return true
  }
}
