import Foundation
import SpamWiseCore
import Evaluation

struct Options {
  static let usage = """
    spamwise-eval --input CORPUS --model MODEL
      [--strength conservative|balanced|aggressive] [--cache DIRECTORY] [--output REPORT.json]
      [--state STATE.json] [--mock-responses RESPONSES.json]
      [--input-price USD_PER_M] [--output-price USD_PER_M] [--cache-price USD_PER_M]
      [--budget-store PATH]
    spamwise-eval --reviewed LABELS.json [--partition held-out|training|all] --model MODEL
      [--strength conservative|balanced|aggressive] [--cache DIRECTORY] [--output REPORT.json]
    spamwise-eval --export inbox|junk|sent --destination DIRECTORY [--limit 500]
    spamwise-eval --compare FROZEN_MANIFEST.json [--output REPORT.json]
    Models: mock, claude-haiku-5-5, claude-sonnet-5-5, claude-opus-5-5, gpt-5.4-mini,
      gemini-3.8-flash, apple-on-device, apple-private-cloud-compute.
    Live calls require SPAMWISE_LIVE_API=1 and the selected provider's API key environment variable.
    Paid calls reserve a conservative bound in the persistent budget store before sending.
    Corpus folders: good/, junk/, and optional graymail/. Reports contain filenames and reasons.
    Exported messages require independent human labels; mailbox placement is not ground truth.
    Reviewed exports default to held-out, reject duplicate content, and report missing retained \
    text.
    --state is prohibited for reviewed held-out/all runs; labels never enter model prompts.
    --budget-store selects a ledger; a different ledger requires separate spending authorization.
    """
  var values: [String: String] = [:]
  var reviewedPartition: ReviewedCorpusPartition {
    get throws {
      guard let partition = ReviewedCorpusPartition(rawValue: values["partition"] ?? "held-out")
      else {
        throw EvaluationError.arguments
      }
      return partition
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
  init(_ arguments: [String]) throws {
    let allowed: Set<String> = [
      "input", "model", "strength", "cache", "output", "state", "mock-responses",
      "input-price", "output-price", "cache-price", "export", "destination", "limit",
      "budget-store",
      "reviewed", "partition", "compare"
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
    guard !(values["input"] != nil && values["reviewed"] != nil),
      values["reviewed"] != nil || values["partition"] == nil
    else { throw EvaluationError.arguments }
    if values["reviewed"] != nil, values["state"] != nil, try reviewedPartition != .training {
      throw EvaluationError.arguments
    }
    _ = try reviewedPartition
    if values["compare"] != nil, !Set(values.keys).isSubset(of: ["compare", "output"]) {
      throw EvaluationError.arguments
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
enum EvaluationError: CorpusEvaluationError, LocalizedError {
  case arguments, emptyCorpus, duplicateMessage, missingMock, liveDisabled, missingKey,
    oversizedFile
  var errorDescription: String? { String(localized: "Couldn’t evaluate the corpus.") }
  var failureReason: String? {
    switch self {
      case .arguments: String(localized: "Invalid arguments. Use --help for usage.")
      case .emptyCorpus: String(localized: "No labeled .eml files found.")
      case .duplicateMessage:
        String(
          localized: "Duplicate message bytes in corpus; remove duplicates before calibration."
        )
      case .missingMock: String(localized: "No mock response exists for this message hash.")
      case .liveDisabled:
        String(
          localized: "Live evaluation requires SPAMWISE_LIVE_API=1. No provider call was made."
        )
      case .missingKey:
        String(
          localized: "Set the selected provider’s API key for this process. The CLI never saves it."
        )
      case .oversizedFile: String(localized: "Corpus message exceeds the 2 MB parser budget.")
    }
  }
}
