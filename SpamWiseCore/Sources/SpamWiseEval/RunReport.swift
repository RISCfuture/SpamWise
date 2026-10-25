import Evaluation
import Foundation
import SpamWiseCore

/**
 The JSON report for one labeled run: metrics, calibration, every message's result, provider
 usage and provenance notes.
 */
struct RunReport: Encodable {
  var model: String
  var strength: FilteringStrength
  var metrics: EvaluationReport
  /// Every message's verdict, category, preference and effective decision, in corpus order.
  var observations: [EvaluationObservation]
  var calibration: ThresholdCalibration
  var calibrationStatus: String
  var cacheHits: Int
  var providerCalls: Int
  var failedProviderCalls: Int
  var newUsage: TokenUsage
  var newEstimatedCostUSD: Double
  var costNote: String
  var evidenceNote: String
  var reviewedCorpus: ReviewedCorpus.Summary?

  init(
    options: ClassifierOptions,
    observations: [EvaluationObservation],
    cache: CachedClassifier,
    reviewed: ReviewedCorpus.Summary? = nil
  ) async {
    model = options.model.description
    strength = options.strength
    metrics = EvaluationReport(observations: observations)
    self.observations = observations
    calibration = ThresholdCalibration(observations: observations, strength: options.strength)
    calibrationStatus = Self.calibrationStatus(metrics: metrics, observations: observations)
    cacheHits = await cache.hits
    let isMock = options.model == .mock
    providerCalls = isMock ? 0 : await cache.providerCalls
    failedProviderCalls = isMock ? 0 : await cache.failedProviderCalls
    newUsage = await cache.newUsage
    newUsage.pricing = options.pricing
    newEstimatedCostUSD = isMock ? 0 : newUsage.estimatedCost
    costNote = """
      Estimated, excludes undisclosed cache-write premiums. Rates use the explicit model’s \
      verified pricing unless overridden; cached reruns incur zero new tokens.
      """
    reviewedCorpus = reviewed
    evidenceNote = Self.evidenceNote(isMock: isMock, reviewed: reviewed)
    if let reviewed, reviewed.partition != .heldOut {
      calibrationStatus +=
        " Training/all partitions are exploratory and cannot establish held-out quality."
    }
  }

  private static func calibrationStatus(
    metrics: EvaluationReport,
    observations: [EvaluationObservation]
  ) -> String {
    var status = """
      Uncalibrated. Selected thresholds are chosen on the training partition and are provisional \
      until validated on a separate held-out partition before production.
      """
    let minimum = ThresholdCalibration.minimumGoodExamples(for: .balanced)
    if metrics.binary.good < minimum {
      let target = ThresholdCalibration.falsePositiveTarget(for: .balanced)
      status += """
         Fewer than \(minimum.formatted(.number)) good examples cannot establish the \
        \(target.formatted(.percent)) Balanced false-positive target, even with zero false \
        positives.
        """
    }
    let partitions = Set(observations.compactMap(\.partition))
    if partitions.count < 2 {
      status += """
         Threshold selection needs both training and held-out observations; evaluate reviewed \
        labels with --partition all.
        """
    }
    return status
  }

  private static func evidenceNote(isMock: Bool, reviewed: ReviewedCorpus.Summary?) -> String {
    let source =
      if let reviewed {
        """
        Retained parsed-message evaluation, partition \(reviewed.partition.rawValue). Truth labels \
        never enter model input. No live DNS, Rspamd, OCR, or Mail access. This statistical \
        content hold-out does not establish independent live full-pipeline quality: reviewed \
        corrections may have influenced user policy or model choice. Missing retained content is \
        counted in reviewedCorpus, not silently evaluated as empty mail.
        """
      } else {
        """
        Offline evidence only: optional RDAP is unknown. --state can supply rules, contacts and \
        account history under account ID eval. Corpus files are split into training and held-out \
        partitions by content hash.
        """
      }
    guard isMock else { return source }
    return source + """
       Mock verdicts are a plumbing check: they bypass the instructions, prompt and model, so they \
      say nothing about classification quality.
      """
  }
}
