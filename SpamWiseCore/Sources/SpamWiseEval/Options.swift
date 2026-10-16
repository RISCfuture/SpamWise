import Foundation
import SpamWiseCore

struct Options {
  static let usage = """
    spamwise-eval --input CORPUS --model mock|claude-haiku-5-5|claude-sonnet-5-5|claude-opus-5-5
      [--strength conservative|balanced|aggressive] [--cache DIRECTORY] [--output REPORT.json]
      [--state STATE.json] [--mock-responses RESPONSES.json]
      [--input-price USD_PER_M] [--output-price USD_PER_M] [--cache-price USD_PER_M]
    spamwise-eval --export inbox|junk|sent --destination DIRECTORY [--limit 500]
    Live calls require SPAMWISE_LIVE_API=1 and ANTHROPIC_API_KEY in the environment.
    Corpus folders: good/, junk/, and optional graymail/. Reports contain filenames and reasons.
    Exported messages require independent human labels; mailbox placement is not ground truth.
    """
  var values: [String: String] = [:]
  init(_ arguments: [String]) throws {
    let allowed: Set<String> = [
      "input", "model", "strength", "cache", "output", "state", "mock-responses",
      "input-price", "output-price", "cache-price", "export", "destination", "limit"
    ]
    guard arguments.count.isMultiple(of: 2) else { throw EvaluationError.arguments }
    for offset in stride(from: 0, to: arguments.count, by: 2) {
      let flag = arguments[offset]
      let name = String(flag.dropFirst(2))
      guard flag.hasPrefix("--"), allowed.contains(name), values[name] == nil else {
        throw EvaluationError.arguments
      }
      values[name] = arguments[offset + 1]
    }
  }
  var model: String { values["model"] ?? "mock" }
  var strength: FilteringStrength {
    get throws {
      guard let strength = FilteringStrength(rawValue: values["strength"] ?? "balanced") else {
        throw EvaluationError.arguments
      }
      return strength
    }
  }
  func required(_ name: String) throws -> String {
    guard let value = values[name], !value.isEmpty else { throw EvaluationError.arguments }
    return value
  }
  func price(_ name: String, default fallback: Double?) throws -> Double? {
    guard let raw = values[name] else { return fallback }
    guard let value = Double(raw), value.isFinite, value >= 0 else {
      throw EvaluationError.arguments
    }
    return value
  }
}
enum EvaluationError: Error, LocalizedError {
  case arguments, emptyCorpus, duplicateMessage, missingMock, liveDisabled, missingKey,
    oversizedFile
  var errorDescription: String? {
    switch self {
      case .arguments: "Invalid arguments. Use --help for usage."
      case .emptyCorpus: "No labeled .eml files found."
      case .duplicateMessage:
        "Duplicate message bytes in corpus; remove duplicates before calibration."
      case .missingMock: "No mock response exists for this message hash."
      case .liveDisabled: "Live evaluation requires SPAMWISE_LIVE_API=1. No provider call was made."
      case .missingKey: "Set ANTHROPIC_API_KEY for the evaluation process. The CLI never saves it."
      case .oversizedFile: "Corpus message exceeds the 2 MB parser budget."
    }
  }
}
