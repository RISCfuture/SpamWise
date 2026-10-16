import Foundation
import SpamWiseCore
import Evaluation

struct RunReport: Encodable {
  var model: String
  var strength: FilteringStrength
  var metrics: EvaluationReport
  var thresholdCandidates: [String: BinaryMetrics]
  var calibrationStatus: String
  var cacheHits: Int
  var providerCalls: Int
  var newUsage: TokenUsage
  var newEstimatedCostUSD: Double?
  var costNote: String
  var evidenceNote: String

  init(
    options: Options,
    report: EvaluationReport,
    raw: [EvaluationObservation],
    cache: CachedClassifier
  ) async throws {
    model = options.model
    strength = try options.strength
    metrics = report
    thresholdCandidates = Dictionary(
      uniqueKeysWithValues: FilteringStrength.allCases.map { strength in
        let rows = raw.map { row -> EvaluationObservation in
          var row = row
          if row.label == .junk && (row.confidence ?? 0) < strength.threshold {
            row.label = .review
          }
          return row
        }
        return (strength.rawValue, EvaluationReport(observations: rows).binary)
      }
    )
    calibrationStatus =
      """
      Uncalibrated. Candidate thresholds are descriptive only; validate on a separate held-out \
      corpus before production.
      """
    if report.binary.good < 1500 {
      calibrationStatus +=
        """
         Fewer than 1,500 good examples cannot establish the 0.2% rule-of-three target, even with \
        zero false positives.
        """
    }
    cacheHits = await cache.hits
    providerCalls = await cache.misses
    newUsage = await cache.newUsage
    let isHaiku = model == ClaudeClassifier.modelID
    let inputPrice = try options.price("input-price", default: isHaiku ? 0.10 : nil)
    let outputPrice = try options.price("output-price", default: isHaiku ? 0.50 : nil)
    let cachePrice = try options.price("cache-price", default: isHaiku ? 0.01 : nil)
    if model == "mock" {
      newEstimatedCostUSD = 0; providerCalls = 0
    } else if let inputPrice, let outputPrice, let cachePrice {
      newEstimatedCostUSD =
        (Double(newUsage.input - newUsage.cached) * inputPrice
          + Double(newUsage.cached) * cachePrice + Double(newUsage.output) * outputPrice)
        / 1_000_000
    }
    costNote =
      """
      Estimated, excludes undisclosed cache-write premiums. Non-Haiku prices require explicit \
      price flags; cached reruns incur zero new tokens.
      """
    evidenceNote =
      """
      Offline evidence only: optional RDAP is unknown. --state can supply rules, contacts and \
      account history under account ID eval. Mock output tests plumbing, not model quality.
      """
  }
}
