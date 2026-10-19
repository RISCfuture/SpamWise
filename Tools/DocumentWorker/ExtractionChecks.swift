import Foundation
import PDFKit

/// In-process extraction checks that need no signing, XPC service or sandbox.
@main
private enum ExtractionChecks {
  private static let fixtureCharacters = 3100
  private static let samples: [(name: String, text: String)] = [
    ("latin", String(repeating: "x", count: fixtureCharacters)),
    ("devanagari-conjuncts", String(repeating: "क्षि", count: fixtureCharacters)),
    ("hindi-words", String(repeating: "नमस्ते दुनिया ", count: fixtureCharacters / 6)),
    (
      "combining-marks",
      String(
        repeating: "a\u{301}\u{302}\u{303}\u{304}\u{305}\u{306}\u{307} ",
        count: fixtureCharacters / 2
      )
    ),
    ("escaped-controls", String(repeating: "\u{1}", count: fixtureCharacters))
  ]
  private static let typesetSamples = ["devanagari-conjuncts", "hindi-words", "combining-marks"]

  static func main() {
    do {
      for sample in samples { try checkTruncation(sample.name, sample.text) }
      for sample in samples where typesetSamples.contains(sample.name) {
        try checkExtraction(sample.name, sample.text)
      }
      print("PASS: document extraction bounds")
    } catch {
      print("FAIL: \(error)")
      exit(1)
    }
  }

  private static func checkTruncation(_ name: String, _ source: String) throws {
    var bounded = BoundedText()
    let complete = bounded.append(source)
    let result = DocumentResult(status: .extracted, text: bounded.text)
    print(
      "truncation-\(name): characters=\(bounded.text.count), reply-bytes=\(result.encoded().count)"
    )
    guard !complete, !bounded.text.isEmpty, source.hasPrefix(bounded.text) else {
      throw ProbeError.failed("truncation-\(name)")
    }
    try verifyWithinReplyLimits("truncation-\(name)", result)
  }

  private static func checkExtraction(_ name: String, _ source: String) throws {
    let pdf = try DocumentFixtures.typeset(source)
    let page = PDFDocument(data: pdf)?.string ?? ""
    let pageBytes = page.reduce(0) { $0 + BoundedText.encodedBytes(of: $1) }
    guard pageBytes > DocumentWorkerLimits.outputBytes else {
      throw ProbeError.failed("extraction-\(name)-fixture-within-limit")
    }
    let result = PDFExtraction.extract(pdf)
    print(
      "extraction-\(name): \(result.status.rawValue), page-bytes=\(pageBytes), "
        + "characters=\(result.text.count), reply-bytes=\(result.encoded().count)"
    )
    guard result.status == .extracted, !result.text.isEmpty else {
      throw ProbeError.failed("extraction-\(name)")
    }
    try verifyWithinReplyLimits("extraction-\(name)", result)
  }

  private static func verifyWithinReplyLimits(_ name: String, _ result: DocumentResult) throws {
    guard result.encoded().count <= DocumentWorkerLimits.outputBytes,
      result.text.count <= DocumentWorkerLimits.textCharacters
    else { throw ProbeError.failed("\(name)-exceeds-reply-limits") }
  }
}
