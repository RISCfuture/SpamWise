public import Foundation
public import SpamWiseCore

/// One independently labeled sample; omitted objectives have no known truth label.
public struct ThreatEvaluationObservation: Codable, Sendable {
  /// Stable deduplicated sample identifier.
  public var sampleID: String
  /// Independently recorded language code, or unknown.
  public var language: String
  /// Explicit objective labels; never inferred from mail-folder membership or another objective.
  public var truth: [ThreatKind: Bool]
  /// Detector result; nil means no assessment, including historical records.
  public var assessment: ThreatAssessment?

  /// Records separate objective labels and coverage for one sample.
  public init(
    sampleID: String,
    language: String,
    truth: [ThreatKind: Bool],
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
    let positive = observations.filter { $0.truth[kind] == true }
    let negative = observations.filter { $0.truth[kind] == false }
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
  /// Largest observations file accepted.
  public static let maximumInputBytes = 20_000_000
  /// Assessment schema used by this report.
  public var schema: String
  /// Metrics by objective.
  public var objectives: [ThreatKind: ThreatMetrics]
  /// Metrics by language and objective, preserving unknown language as its own group.
  public var languages: [String: [ThreatKind: ThreatMetrics]]

  /// Rejects duplicate samples, blank identities and invalid findings before reporting.
  public init(observations: [ThreatEvaluationObservation]) throws {
    try Self.validate(observations)
    schema = ThreatAssessment.schemaID
    objectives = Self.metrics(observations)
    languages = Dictionary(grouping: observations, by: \.language).mapValues(Self.metrics)
  }

  /// Loads and validates a bounded JSON array of observations.
  public init(contentsOf url: URL) throws {
    let data = try ThreatReportError.boundedContents(of: url, limit: Self.maximumInputBytes)
    try self.init(
      observations: JSONDecoder().decode([ThreatEvaluationObservation].self, from: data)
    )
  }

  private static func validate(_ observations: [ThreatEvaluationObservation]) throws {
    guard !observations.isEmpty else { throw ThreatReportError.noObservations }
    var seen: Set<String> = []
    for observation in observations {
      try requireIdentity(observation)
      guard seen.insert(observation.sampleID).inserted else {
        throw ThreatReportError.duplicateSample(observation.sampleID)
      }
      try requireValidAssessment(observation)
    }
  }

  private static func requireIdentity(_ observation: ThreatEvaluationObservation) throws {
    guard !isBlank(observation.sampleID) else { throw ThreatReportError.blankSampleID }
    guard !isBlank(observation.language) else {
      throw ThreatReportError.blankLanguage(sampleID: observation.sampleID)
    }
  }

  private static func requireValidAssessment(_ observation: ThreatEvaluationObservation) throws {
    do { try observation.assessment?.validate() } catch {
      throw ThreatReportError.invalidAssessment(sampleID: observation.sampleID)
    }
  }

  private static func isBlank(_ text: String) -> Bool {
    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private static func metrics(_ observations: [ThreatEvaluationObservation]) -> [ThreatKind:
    ThreatMetrics]
  {
    Dictionary(
      uniqueKeysWithValues: ThreatKind.allCases.map {
        ($0, ThreatMetrics(kind: $0, observations: observations))
      }
    )
  }
}

/// Objective observations that can't produce a threat report; no detector or Mail access occurs.
public enum ThreatReportError: CorpusEvaluationError, BoundedInputError, Sendable, Equatable,
  LocalizedError
{
  /// The observations array is empty.
  case noObservations
  /// Two observations share one sample identifier.
  case duplicateSample(String)
  /// An observation has a blank sample identifier.
  case blankSampleID
  /// An observation has a blank language code.
  case blankLanguage(sampleID: String)
  /// An observation's assessment has invalid findings or coverage.
  case invalidAssessment(sampleID: String)
  /// The observations path names a directory or other non-regular file.
  case notRegularFile(URL)
  /// The observations file is larger than the report accepts.
  case fileTooLarge(URL, limit: Int)

  /// General description of the failed report.
  public var errorDescription: String? {
    String(localized: "Couldn’t build the threat report.")
  }
  /// The observation that prevents a valid report.
  public var failureReason: String? {
    switch self {
      case .noObservations: String(localized: "The observations file contains no samples.")
      case .duplicateSample(let id): String(localized: "Sample \(id) appears more than once.")
      case .blankSampleID: String(localized: "An observation has a blank sample ID.")
      case .blankLanguage(let id): String(localized: "Sample \(id) has a blank language code.")
      case .invalidAssessment(let id):
        String(localized: "Sample \(id) has an invalid assessment.")
      case .notRegularFile(let url): String(localized: "\(url.path) isn’t a regular file.")
      case let .fileTooLarge(url, limit):
        String(
          localized:
            "\(url.path) exceeds the \(limit.formatted(.byteCount(style: .file))) input limit."
        )
    }
  }
  /// The correction to make to the observations.
  public var recoverySuggestion: String? {
    switch self {
      case .noObservations, .notRegularFile:
        String(localized: "Pass a JSON array of labeled observations.")
      case .duplicateSample: String(localized: "Merge or remove the repeated observations.")
      case .blankSampleID, .blankLanguage:
        String(localized: "Record a sample ID and a language code, or “unknown”, for every sample.")
      case .invalidAssessment:
        String(
          localized: "Regenerate the assessment, or omit it to report the sample as unassessed."
        )
      case .fileTooLarge: String(localized: "Split the observations into smaller files.")
    }
  }
}
