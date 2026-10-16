import Foundation
public import SpamWiseCore

/// One independently labeled sample; omitted objectives have no known truth label.
public struct ThreatEvaluationObservation: Codable, Sendable {
  /// Stable deduplicated sample identifier.
  public var sampleID: String
  /// Independently recorded language code, or unknown.
  public var language: String
  /// Explicit objective labels; never inferred from mail-folder membership or another objective.
  public var truth: [String: Bool]
  /// Detector result; nil means no assessment, including historical records.
  public var assessment: ThreatAssessment?

  /// Records separate objective labels and coverage for one sample.
  public init(
    sampleID: String,
    language: String,
    truth: [String: Bool],
    assessment: ThreatAssessment?
  ) {
    self.sampleID = sampleID; self.language = language; self.truth = truth
    self.assessment = assessment
  }
}

/// Objective-specific confusion counts with unknown coverage kept explicit.
public struct ThreatMetrics: Codable, Sendable {
  /// Samples with explicit positive truth labels.
  public var positives: Int
  /// Samples with explicit negative truth labels.
  public var negatives: Int
  /// Samples lacking an objective label, excluded from accuracy calculations.
  public var unlabeled: Int
  /// Labeled samples without an assessed finding.
  public var unassessed: Int
  /// Positive labels detected within the stated coverage.
  public var truePositives: Int
  /// Negative labels incorrectly detected.
  public var falsePositives: Int
  /// Explicit negative labels that were actually assessed.
  public var assessedNegatives: Int
  /// Detection recall counts unassessed positives as missed, never as successful negatives.
  public var recall: Double?
  /// Precision among detected findings with known truth labels.
  public var precision: Double?
  /// False-positive upper bound among assessed negative samples only.
  public var falsePositiveUpper95: Double?

  init(kind: ThreatKind, observations: [ThreatEvaluationObservation]) {
    let positive = observations.filter { $0.truth[kind.rawValue] == true }
    let negative = observations.filter { $0.truth[kind.rawValue] == false }
    positives = positive.count; negatives = negative.count
    unlabeled = observations.count - positives - negatives
    let labeled = positive + negative
    unassessed = labeled.filter { Self.status($0, kind: kind) == .unknown }.count
    truePositives = positive.filter { Self.status($0, kind: kind) == .detected }.count
    falsePositives = negative.filter { Self.status($0, kind: kind) == .detected }.count
    assessedNegatives = negative.filter { Self.status($0, kind: kind) != .unknown }.count
    recall = positives == 0 ? nil : Double(truePositives) / Double(positives)
    let detected = truePositives + falsePositives
    precision = detected == 0 ? nil : Double(truePositives) / Double(detected)
    falsePositiveUpper95 = BinomialBound.upper95(errors: falsePositives, trials: assessedNegatives)
  }

  private static func status(_ observation: ThreatEvaluationObservation, kind: ThreatKind)
    -> ThreatStatus
  {
    observation.assessment?.finding(for: kind)?.status ?? .unknown
  }
}

/// Independent objective metrics; Inbox/Junk preference labels never supply threat truth.
public struct ThreatEvaluationReport: Codable, Sendable {
  /// Assessment schema used by this report.
  public var schema: String
  /// Metrics by objective.
  public var objectives: [String: ThreatMetrics]
  /// Metrics by language and objective, preserving unknown language as its own group.
  public var languages: [String: [String: ThreatMetrics]]

  /// Rejects duplicate samples, invalid findings and unknown objective names before reporting.
  public init(observations: [ThreatEvaluationObservation]) throws {
    guard !observations.isEmpty,
      Set(observations.map(\.sampleID)).count == observations.count,
      observations.allSatisfy({ row in
        !row.sampleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          && !row.language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          && row.truth.keys.allSatisfy { ThreatKind(rawValue: $0) != nil }
      })
    else { throw ComparisonError.invalidManifest }
    for observation in observations { try observation.assessment?.validate() }
    schema = ThreatAssessment.schemaID
    objectives = Self.metrics(observations)
    languages = Dictionary(grouping: observations, by: \.language).mapValues(Self.metrics)
  }

  private static func metrics(_ observations: [ThreatEvaluationObservation]) -> [String:
    ThreatMetrics]
  {
    Dictionary(
      uniqueKeysWithValues: ThreatKind.allCases.map {
        ($0.rawValue, ThreatMetrics(kind: $0, observations: observations))
      }
    )
  }
}
