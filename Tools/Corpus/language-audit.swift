import Foundation
import NaturalLanguage

private struct DevelopmentText: Decodable {
  let id: String
  let text: String
}

private struct LanguageEstimate: Encodable {
  let id: String
  let language: String
  let confidence: Double
}

private enum RecognitionPolicy {
  static let characterLimit = 20_000
  static let minimumLetters = 40
  static let minimumConfidence = 0.8
  static let minimumMargin = 0.2

  static func estimate(_ record: DevelopmentText) -> LanguageEstimate {
    let text = String(record.text.prefix(characterLimit))
    guard text.filter(\.isLetter).count >= minimumLetters else {
      return LanguageEstimate(id: record.id, language: "unknown", confidence: 0)
    }
    let recognizer = NLLanguageRecognizer()
    recognizer.processString(text)
    let hypotheses = recognizer.languageHypotheses(withMaximum: 2)
      .sorted { $0.value > $1.value }
    guard let first = hypotheses.first else {
      return LanguageEstimate(id: record.id, language: "unknown", confidence: 0)
    }
    let nextConfidence = hypotheses.dropFirst().first?.value ?? 0
    let accepted =
      first.value >= minimumConfidence
      && first.value - nextConfidence >= minimumMargin
    return LanguageEstimate(
      id: record.id,
      language: accepted ? first.key.rawValue : "unknown",
      confidence: first.value
    )
  }
}

let data = FileHandle.standardInput.readDataToEndOfFile()
private let records = try JSONDecoder().decode([DevelopmentText].self, from: data)
let output = try JSONEncoder().encode(records.map(RecognitionPolicy.estimate))
try FileHandle.standardOutput.write(contentsOf: output)
