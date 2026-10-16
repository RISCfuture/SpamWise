public import Foundation
import SpamWiseCore

/// Offline paired-system metrics from an explicitly reviewed, frozen comparison manifest.
public struct ComparisonReport: Codable, Sendable {
  private static let maximumMessages = 10_000
  private static let maximumRuns = 8
  private static let falsePositiveTarget = 0.002
  /// Caller-supplied identifier of the immutable holdout.
  public let holdoutID: String
  /// Hash of the complete input manifest for reproducibility.
  public let manifestHash: String
  /// Cohort size shared by every system; missing predictions must be explicit abstentions.
  public let messages: Int
  /// Candidate-folder provenance, independent of the human truth labels.
  public let sourceCounts: [String: Int]
  /// Metrics for each named system/configuration on exactly the same messages.
  public let systems: [SystemComparison]
  /// Whether every system attests unseen data and frozen learning and meets the statistical bound.
  public let eligibleForBoundedComparison: Bool
  /// Limits of the manifest's assertions and observational measurements.
  public let caveat: String

  /// Validates a bounded manifest and recomputes all metrics without mail or provider access.
  public init(data: Data) throws {
    guard data.count <= 20_000_000 else { throw ComparisonError.invalidManifest }
    let manifest = try JSONDecoder().decode(ComparisonManifest.self, from: data)
    try Self.validate(manifest)
    holdoutID = manifest.holdoutID
    manifestHash = stableHash(data)
    messages = manifest.messages.count
    sourceCounts = Dictionary(grouping: manifest.messages, by: { $0.source.rawValue }).mapValues(
      \.count
    )
    systems = try manifest.runs.map { try SystemComparison(run: $0, messages: manifest.messages) }
    eligibleForBoundedComparison = systems.allSatisfy {
      $0.priorExposure == "none"
        && ($0.metrics.binary.falsePositiveUpper95 ?? 1) <= Self.falsePositiveTarget
    }
    caveat = """
      Human review, campaign grouping, frozen learning and prior exposure are caller attestations, \
      not independently verified. Graymail is separate. Unclassified/Review retain mail and count \
      as missed junk. Latency and resource figures describe the supplied measurements; cached and \
      live runs must use different configuration IDs. Do not tune on this holdout or infer \
      superiority from a small sample. Review time is observed effort, not a predicted saving.
      """
  }
  private static func validate(_ manifest: ComparisonManifest) throws {
    let ids = manifest.messages.map(\.id), campaigns = manifest.messages.map(\.campaign)
    guard manifest.schema == 1, manifest.humanReviewed, !manifest.holdoutID.isEmpty,
      ISO8601DateFormatter().date(from: manifest.frozenAt) != nil,
      (1...maximumMessages).contains(ids.count), (2...maximumRuns).contains(manifest.runs.count),
      Set(ids).count == ids.count, Set(campaigns).count == campaigns.count,
      ids.allSatisfy({ !$0.isEmpty }), campaigns.allSatisfy({ !$0.isEmpty }),
      Set(campaigns).isDisjoint(with: manifest.trainingCampaigns),
      Set(manifest.runs.map(\.system)).count == manifest.runs.count,
      manifest.runs.allSatisfy({
        $0.learningFrozen && !$0.system.isEmpty && !$0.configurationID.isEmpty
      })
    else { throw ComparisonError.invalidManifest }
  }
}

/// Quality, operational effort and performance for one frozen system configuration.
public struct SystemComparison: Codable, Sendable {
  /// Product or experiment name supplied by the evaluator.
  public let system: String
  /// Immutable model, policy, learning-state and cache-mode identity supplied by the evaluator.
  public let configurationID: String
  /// Declared prior exposure: none, known, or unknown.
  public let priorExposure: String
  /// Recomputed quality metrics using the manifest's human labels.
  public let metrics: EvaluationReport
  /// Count of explicit Review and unclassified outputs.
  public let abstentions: Int
  /// Nearest-rank median and 95th percentile of complete per-message elapsed measurements.
  public let latencyP50Sec: Double?
  /// Nearest-rank 95th percentile, absent if any measurement is missing.
  public let latencyP95Sec: Double?
  /// Observed whole-run throughput, including the caller's chosen setup and concurrency.
  public let messagesPerSec: Double
  /// Measured CPU time, if provided; never inferred from elapsed time.
  public let cpuSec: Double?
  /// Measured peak resident memory, if provided.
  public let peakMemoryBytes: UInt64?
  /// Measured or estimated provider charge, if provided.
  public let costUSD: Double?
  /// Declared cost provenance, required when a charge is provided.
  public let costBasis: String?
  /// Review minutes per thousand messages, absent unless every message has an observation.
  public let reviewMinPerThousand: Double?
  /// Corrections per thousand messages, absent unless every message has an observation.
  public let correctionsPerThousand: Double?

  fileprivate init(run: ComparisonRun, messages: [ComparisonMessage]) throws {
    let ids = run.results.map(\.id)
    guard Set(ids).count == ids.count, Set(ids) == Set(messages.map(\.id)),
      ["none", "known", "unknown"].contains(run.priorExposure),
      run.elapsedSec.isFinite, run.elapsedSec > 0,
      [run.cpuSec, run.costUSD].compactMap({ $0 }).allSatisfy(Self.validMeasurement),
      run.costUSD == nil || ["measured", "estimated"].contains(run.costBasis ?? ""),
      run.results.allSatisfy({ result in
        [result.latencySec, result.reviewSec].compactMap({ $0 }).allSatisfy(Self.validMeasurement)
      })
    else { throw ComparisonError.invalidManifest }
    let truths = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0.truth) })
    system = run.system; configurationID = run.configurationID; priorExposure = run.priorExposure
    metrics = EvaluationReport(
      observations: run.results.map {
        EvaluationObservation(
          file: $0.id,
          truth: truths[$0.id]!,
          label: $0.label,
          confidence: nil,
          path: "comparison",
          reason: $0.reason ?? "No reason supplied"
        )
      }
    )
    abstentions = run.results.filter { $0.label == nil || $0.label == .review }.count
    let latencies = run.results.compactMap(\.latencySec).sorted()
    latencyP50Sec =
      latencies.count == messages.count ? Self.percentile(latencies, fraction: 0.5) : nil
    latencyP95Sec =
      latencies.count == messages.count ? Self.percentile(latencies, fraction: 0.95) : nil
    messagesPerSec = Double(messages.count) / run.elapsedSec
    cpuSec = run.cpuSec; peakMemoryBytes = run.peakMemoryBytes
    costUSD = run.costUSD; costBasis = run.costBasis
    let review = run.results.compactMap(\.reviewSec),
      corrections = run.results.compactMap(\.corrections)
    reviewMinPerThousand =
      review.count == messages.count
      ? review.reduce(0, +) / 60 * 1000 / Double(messages.count) : nil
    correctionsPerThousand =
      corrections.count == messages.count
      ? corrections.reduce(0) { $0 + Double($1) } * 1000 / Double(messages.count) : nil
  }
  private static func validMeasurement(_ value: Double) -> Bool { value.isFinite && value >= 0 }
  private static func percentile(_ values: [Double], fraction: Double) -> Double {
    values[max(0, Int(ceil(Double(values.count) * fraction)) - 1)]
  }
}

private struct ComparisonManifest: Decodable {
  let schema: Int
  let holdoutID: String
  let frozenAt: String
  let humanReviewed: Bool
  let trainingCampaigns: Set<String>
  let messages: [ComparisonMessage]
  let runs: [ComparisonRun]
}
private struct ComparisonMessage: Decodable {
  let id: String
  let campaign: String
  let truth: EvaluationTruth
  let source: Source
  enum Source: String, Decodable { case spamsieve, server, unknown, other }
}
private struct ComparisonRun: Decodable {
  let system: String
  let configurationID: String
  let learningFrozen: Bool
  let priorExposure: String
  let elapsedSec: Double
  let cpuSec: Double?
  let peakMemoryBytes: UInt64?
  let costUSD: Double?
  let costBasis: String?
  let results: [Result]
  struct Result: Decodable {
    let id: String
    let label: MailLabel?
    let latencySec: Double?
    let reviewSec: Double?
    let corrections: UInt?
    let reason: String?
  }
}

/// Manifest validation failures; no provider or Mail operation is performed.
public enum ComparisonError: CorpusEvaluationError, LocalizedError {
  /// The cohort, measurements or freeze attestations are incomplete or inconsistent.
  case invalidManifest
  /// General description of the failed comparison.
  public var errorDescription: String? { String(localized: "Couldn’t compare the frozen runs.") }
  /// Required comparison boundaries that must hold before metrics are produced.
  public var failureReason: String? {
    String(
      localized:
        "Use human-reviewed, campaign-disjoint messages and complete paired results with frozen learning."
    )
  }
}
