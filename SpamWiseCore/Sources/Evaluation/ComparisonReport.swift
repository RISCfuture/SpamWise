public import Foundation
import SpamWiseCore

/// Offline paired-system metrics from an explicitly reviewed, frozen comparison manifest.
public struct ComparisonReport: Codable, Sendable {
  /// Largest manifest accepted.
  public static let maximumManifestBytes = 20_000_000
  /// Supported manifest schema version.
  public static let schema = 1
  static let messageCounts = 1...10_000
  static let runCounts = 2...8
  private static let falsePositiveTarget = ThresholdCalibration.falsePositiveTarget(for: .balanced)
  /// Caller-supplied identifier of the immutable holdout.
  public let holdoutID: String
  /// When the compared systems' learning was frozen.
  public let frozenAt: Date
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
    guard data.count <= Self.maximumManifestBytes else {
      throw ComparisonManifestError.manifestTooLarge(limit: Self.maximumManifestBytes)
    }
    let manifest = try ComparisonManifest.decoder.decode(ComparisonManifest.self, from: data)
    try manifest.validate()
    holdoutID = manifest.holdoutID; frozenAt = manifest.frozenAt
    manifestHash = stableHash(data)
    messages = manifest.messages.count
    sourceCounts = Dictionary(grouping: manifest.messages, by: { $0.source.rawValue }).mapValues(
      \.count
    )
    systems = try manifest.runs.map { try SystemComparison(run: $0, messages: manifest.messages) }
    eligibleForBoundedComparison = systems.allSatisfy {
      $0.priorExposure == PriorExposure.none
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

  /// Loads and validates a bounded manifest file.
  public init(contentsOf url: URL) throws {
    try self.init(
      data: ComparisonManifestError.boundedContents(of: url, limit: Self.maximumManifestBytes)
    )
  }
}

/// How much a compared system may have seen the holdout before the frozen run.
public enum PriorExposure: String, Codable, Sendable {
  /// The system never saw any holdout message.
  case none
  /// The system saw some holdout messages.
  case known
  /// Whether the system saw holdout messages is unknown.
  case unknown
}

/// Provenance of a compared system's reported charge.
public enum CostBasis: String, Codable, Sendable {
  /// Billed or metered by the provider.
  case measured
  /// Computed from token counts and published rates.
  case estimated
}

/// Quality, operational effort and performance for one frozen system configuration.
public struct SystemComparison: Codable, Sendable {
  private static let secondsPerMinute = 60.0
  private static let perThousand = 1000.0
  private static let medianFraction = 0.5
  private static let tailFraction = 0.95
  /// Product or experiment name supplied by the evaluator.
  public let system: String
  /// Immutable model, policy, learning-state and cache-mode identity supplied by the evaluator.
  public let configurationID: String
  /// Declared prior exposure to the holdout.
  public let priorExposure: PriorExposure
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
  public let costBasis: CostBasis?
  /// Review minutes per thousand messages, absent unless every message has an observation.
  public let reviewMinPerThousand: Double?
  /// Corrections per thousand messages, absent unless every message has an observation.
  public let correctionsPerThousand: Double?

  init(run: ComparisonRun, messages: [ComparisonMessage]) throws {
    try run.validate(against: messages)
    let truths = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0.truth) })
    system = run.system; configurationID = run.configurationID; priorExposure = run.priorExposure
    metrics = EvaluationReport(
      observations: run.results.compactMap { result in
        truths[result.id].map {
          EvaluationObservation(
            file: result.id,
            truth: $0,
            label: result.label,
            confidence: nil,
            path: nil,
            reason: result.reason ?? "No reason supplied"
          )
        }
      }
    )
    abstentions = run.results.filter { $0.label == nil || $0.label == .review }.count
    let latencies = run.results.compactMap(\.latencySec).sorted()
    let complete = latencies.count == messages.count
    latencyP50Sec = complete ? Self.percentile(latencies, fraction: Self.medianFraction) : nil
    latencyP95Sec = complete ? Self.percentile(latencies, fraction: Self.tailFraction) : nil
    messagesPerSec = Double(messages.count) / run.elapsedSec
    cpuSec = run.cpuSec; peakMemoryBytes = run.peakMemoryBytes
    costUSD = run.costUSD; costBasis = run.costBasis
    let review = run.results.compactMap(\.reviewSec),
      corrections = run.results.compactMap(\.corrections)
    let count = Double(messages.count)
    reviewMinPerThousand =
      review.count == messages.count
      ? review.reduce(0, +) / Self.secondsPerMinute * Self.perThousand / count : nil
    correctionsPerThousand =
      corrections.count == messages.count
      ? corrections.reduce(0) { $0 + Double($1) } * Self.perThousand / count : nil
  }

  private static func percentile(_ values: [Double], fraction: Double) -> Double {
    values[max(0, Int(ceil(Double(values.count) * fraction)) - 1)]
  }
}
