import Foundation
import SpamWiseCore
import Evaluation

struct RunReport: Encodable {
  private static let minimumGoodExamples = 1500
  private static let tokensPerMillion: Double = 1_000_000
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
  var reviewedCorpus: ReviewedCorpus.Summary?

  init(
    options: Options,
    report: EvaluationReport,
    raw: [EvaluationObservation],
    cache: CachedClassifier,
    reviewed: ReviewedCorpus.Summary? = nil
  ) async throws {
    model = options.model
    reviewedCorpus = reviewed
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
    if report.binary.good < Self.minimumGoodExamples {
      calibrationStatus +=
        """
         Fewer than 1,500 good examples cannot establish the 0.2% rule-of-three target, even with \
        zero false positives.
        """
    }
    cacheHits = await cache.hits
    providerCalls = await cache.misses
    newUsage = await cache.newUsage
    let pricing = ModelIdentifier(rawValue: model).map { ModelTokenPricing.rates(for: $0) }
    let inputPrice = try options.price("input-price", default: pricing?.input)
    let outputPrice = try options.price("output-price", default: pricing?.output)
    let cachePrice = try options.price("cache-price", default: pricing?.cached)
    if model == "mock" {
      newEstimatedCostUSD = 0; providerCalls = 0
    } else if let inputPrice, let outputPrice, let cachePrice {
      newEstimatedCostUSD =
        (Double(newUsage.input - newUsage.cached) * inputPrice
          + Double(newUsage.cached) * cachePrice + Double(newUsage.output) * outputPrice)
        / Self.tokensPerMillion
    }
    costNote =
      """
      Estimated, excludes undisclosed cache-write premiums. Rates use the explicit model's \
      verified pricing unless overridden; cached reruns incur zero new tokens.
      """
    evidenceNote =
      """
      Offline evidence only: optional RDAP is unknown. --state can supply rules, contacts and \
      account history under account ID eval. Mock output tests plumbing, not model quality.
      """
    if let reviewed {
      evidenceNote = """
        Retained parsed-message evaluation, partition \(reviewed.partition.rawValue). Truth labels \
        never enter model input. No live DNS, Rspamd, OCR, or Mail access. This statistical \
        content hold-out does not establish independent live full-pipeline quality: reviewed \
        corrections may have influenced user policy or model choice. Missing retained content is \
        counted in reviewedCorpus, not silently evaluated as empty mail.
        """
      if reviewed.partition != .heldOut {
        calibrationStatus +=
          " Training/all partitions are exploratory and cannot establish held-out quality."
      }
    }
  }
}
