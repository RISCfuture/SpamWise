public import Classifier
public import Foundation
public import MessageModel
public import Signals

/// Deterministic content split that offline evaluation uses; product learning trains on every label.
public enum LearningPartition: String, Codable, Sendable {
  /// Selected when evaluating the training split.
  case training
  /// Selected by default when evaluating reviewed labels.
  case heldOut
}
/// Evidence provenance distinguishes explicit corrections from classifier predictions.
public enum LearningProvenance: String, Codable, Sendable {
  /// A label selected by the user.
  case explicitCorrection
  /// A prediction admitted by the independent learning gates.
  case highConfidencePrediction
}

/// Bounded features and tokens for local learning without retaining complete message bodies.
public struct LearningSample: Codable, Sendable, Equatable, Identifiable {
  static let hashCharacters = 64
  private static let maximumIdentityCharacters = 8000
  private static let maximumTokens = 128
  private static let maximumTokenCharacters = 40
  private static let partitionPrefixCharacters = 2
  private static let heldOutPartitionDivisor: UInt8 = 5
  /// Content-based identity used to prevent duplicate training.
  public let id: String
  /// Date the latest label was recorded.
  public let date: Date
  /// Latest accepted label.
  public let label: MailLabel
  /// Whether a user or classifier supplied the label.
  public let provenance: LearningProvenance
  /// Distinct tokens with the smallest stable hashes, bounded to 128.
  public let tokens: [String]
  /// Bounded named numeric features.
  public let features: LearningFeatures
  /// Stable identity ignores delivery headers so duplicate content stays in one partition.
  public static func identity(for message: ParsedMessage) -> String {
    stableHash(
      Data(
        (message.subject.lowercased() + "\n" + message.text.lowercased()).prefix(
          maximumIdentityCharacters
        ).utf8
      )
    )
  }
}

/// A content signature created only from an explicit user correction.
public struct CampaignFingerprint: Codable, Sendable, Equatable, Identifiable {
  /// Content identity of the corrected message.
  public let id: String
  /// The explicit correction date.
  public let date: Date
  /// Junk signatures support campaign matches; Inbox and Review signatures suppress them.
  public let label: MailLabel
  /// DMARC-authenticated sender-domain anchors; a Junk match requires a shared anchor.
  public let anchors: [String]
  /// Bounded hashes of meaningful consecutive word sequences.
  public let shingles: [String]
}

/// An authenticated near-duplicate of an explicit Junk correction; it routes mail to Review, never Junk.
public struct CampaignMatch: Codable, Sendable, Equatable {
  /// Supporting explicit correction identity.
  public let fingerprintID: String
  /// Uncalibrated Jaccard content overlap.
  public let similarity: Double
}

/// Optional weak statistical signals; neither margin is a calibrated probability.
public struct LearningEstimate: Codable, Sendable, Equatable {
  /// Smoothed lexical log odds; positive means more Junk-like training words.
  public var bayesLogOdds: Double?
  /// L2-regularized linear logit; positive means more Junk-like evidence.
  public var logisticMargin: Double?
  /// Explicit binary corrections eligible for training.
  public var trainingCount: Int
}

/// Bounded, deterministic local learning state; callers apply rule and relationship gates first.
public struct LearningState: Codable, Sendable, Equatable {
  private static let sampleLimit = 10_000
  private static let fingerprintLimit = 1000
  private static let predictionConfidenceRange = 99...100
  private static let minimumReviewedSamplesPerClass = 20
  private static let samplesPerPrediction = 5
  private static let reviewedSamplesPerPrediction = 4
  private static let contradictoryBayesMagnitude = 1.0
  private static let contradictoryLogisticMagnitude = 0.5
  /// Latest bounded labels, ordered newest first with a stable identity tie break.
  public private(set) var samples: [LearningSample] = []
  /// Explicit campaign examples and Inbox or Review suppressions.
  public private(set) var fingerprints: [CampaignFingerprint] = []
  /// Maximum retained examples, capped at 10,000.
  public let maximumSamples: Int
  /// Maximum retained campaign signatures, capped at 1,000.
  public let maximumFingerprints: Int
  /// Explicit binary training examples; classifier predictions and Review labels are excluded.
  public var trainingSamples: [LearningSample] {
    samples.filter { $0.provenance == .explicitCorrection && $0.label != .review }
  }

  /// Creates empty state with bounded retention limits.
  public init(maximumSamples: Int = 10000, maximumFingerprints: Int = 1000) {
    self.maximumSamples = min(Self.sampleLimit, max(1, maximumSamples))
    self.maximumFingerprints = min(Self.fingerprintLimit, max(1, maximumFingerprints))
  }

  /**
   Decodes persisted state, defaulting missing collections to empty, clamping retention limits
   and discarding samples or fingerprints that violate current bounds.
   */
  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      maximumSamples: try values.decodeIfPresent(Int.self, forKey: .maximumSamples)
        ?? Self.sampleLimit,
      maximumFingerprints: try values.decodeIfPresent(Int.self, forKey: .maximumFingerprints)
        ?? Self.fingerprintLimit
    )
    samples = try values.decodeIfPresent([LearningSample].self, forKey: .samples) ?? []
    fingerprints =
      try values.decodeIfPresent([CampaignFingerprint].self, forKey: .fingerprints) ?? []
    samples.removeAll { !$0.isValid }
    fingerprints.removeAll { !$0.isValid }
    enforceBounds()
  }

  /**
   Stores an explicit correction, replacing the same content's prior label and campaign evidence.

   - Parameters:
     - message: The corrected message.
     - evidence: The evidence gathered for `message`.
     - label: The label the user chose.
     - sampleID: The sample's identity, when it differs from the identity of
       `message`, such as the identity of the text that was classified.
     - date: When the correction was made.
   */
  public mutating func recordCorrection(
    message: ParsedMessage,
    evidence: EvidenceBundle,
    label: MailLabel,
    sampleID: String? = nil,
    date: Date = .now
  ) {
    let sample = LearningSample.make(
      message: message,
      evidence: evidence,
      label: label,
      provenance: .explicitCorrection,
      id: sampleID,
      date: date
    )
    samples.removeAll { $0.id == sample.id }
    samples.append(sample)
    fingerprints.removeAll { $0.id == sample.id }
    if let shingles = CampaignContent.shingles(message) {
      withdrawFingerprints(contradicting: label, overlapping: shingles)
      if label != .junk { withdrawJunkPredictions(coveredBy: sample) }
      if let signature = CampaignContent.fingerprint(
        message: message,
        shingles: shingles,
        evidence: evidence,
        label: label,
        date: date
      ) {
        fingerprints.append(signature.identified(as: sample.id))
      }
    }
    enforceBounds()
  }

  /// Admits only independently high-confidence, noncontradictory binary predictions into Bayes training.
  @discardableResult public mutating func admitPrediction(
    message: ParsedMessage,
    evidence: EvidenceBundle,
    verdict: Verdict,
    hasContradiction: Bool,
    date: Date = .now
  ) -> Bool {
    let identity = LearningSample.identity(for: message)
    guard !hasContradiction, Self.predictionConfidenceRange.contains(verdict.confidence),
      verdict.label != .review,
      !verdict.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      evidence.contact != true, evidence.senderHistory.replyCount == 0,
      evidence.senderHistory.receiptCount == 0,
      !samples.contains(where: { $0.id == identity })
    else { return false }
    let reviewed = trainingSamples
    guard
      StatisticalLearning.hasMinimumClasses(
        reviewed,
        perClass: Self.minimumReviewedSamplesPerClass
      ),
      samples.filter({ $0.provenance == .highConfidencePrediction }).count
        < min(
          maximumSamples / Self.samplesPerPrediction,
          reviewed.count / Self.reviewedSamplesPerPrediction
        )
    else { return false }
    let score = StatisticalLearning.bayes(message: message, reviewed: reviewed, predictions: [])
    if let score, abs(score) >= Self.contradictoryBayesMagnitude,
      (score > 0) != (verdict.label == .junk)
    {
      return false
    }
    if let margin = StatisticalLearning.logistic(evidence: evidence, reviewed: reviewed),
      abs(margin) >= Self.contradictoryLogisticMagnitude, (margin > 0) != (verdict.label == .junk)
    {
      return false
    }
    if verdict.label == .junk
      && CampaignContent.isSuppressed(message: message, fingerprints: fingerprints)
    {
      return false
    }
    samples.append(
      LearningSample.make(
        message: message,
        evidence: evidence,
        label: verdict.label,
        provenance: .highConfidencePrediction,
        date: date
      )
    )
    enforceBounds()
    return true
  }

  /// Returns an authenticated near-duplicate Junk campaign unless an Inbox or Review signature suppresses it.
  public func campaignMatch(for message: ParsedMessage, evidence: EvidenceBundle) -> CampaignMatch?
  {
    CampaignContent.match(message: message, evidence: evidence, fingerprints: fingerprints)
  }
  /// Removes one explicit sample and its campaign signature without changing sender rules.
  public mutating func forget(sampleID: String) {
    samples.removeAll { $0.id == sampleID }
    fingerprints.removeAll { $0.id == sampleID }
  }
  /// Relabels retained features without requiring a body; campaign signatures are withdrawn.
  public mutating func relabel(sampleID: String, label: MailLabel, date: Date = .now) {
    guard let sample = samples.first(where: { $0.id == sampleID }) else { return }
    forget(sampleID: sampleID)
    samples.append(
      LearningSample(
        id: sample.id,
        date: date,
        label: label,
        provenance: .explicitCorrection,
        tokens: sample.tokens,
        features: sample.features
      )
    )
    enforceBounds()
  }

  /**
   Keeps only the explicit samples and campaign signatures that `labels` still holds.

   Samples whose label changed take the new label, and signatures whose label changed are
   withdrawn. Admitted predictions are kept.

   - Parameter labels: Current labels by sample identity.
   */
  public mutating func retainExplicit(matching labels: [String: MailLabel]) {
    samples = samples.compactMap { sample in
      guard sample.provenance == .explicitCorrection else { return sample }
      guard let label = labels[sample.id] else { return nil }
      return LearningSample(
        id: sample.id,
        date: sample.date,
        label: label,
        provenance: sample.provenance,
        tokens: sample.tokens,
        features: sample.features
      )
    }
    fingerprints.removeAll { labels[$0.id] != $0.label }
    enforceBounds()
  }

  /// Computes bounded statistical estimates only after minimum reviewed-data gates pass.
  public func estimate(message: ParsedMessage, evidence: EvidenceBundle) -> LearningEstimate {
    let reviewed = trainingSamples
    let predictions = samples.filter { $0.provenance == .highConfidencePrediction }
    return LearningEstimate(
      bayesLogOdds: StatisticalLearning.bayes(
        message: message,
        reviewed: reviewed,
        predictions: predictions
      ),
      logisticMargin: StatisticalLearning.logistic(evidence: evidence, reviewed: reviewed),
      trainingCount: reviewed.count
    )
  }

  /// The latest explicit label wins over overlapping signatures of the opposite disposition.
  private mutating func withdrawFingerprints(
    contradicting label: MailLabel,
    overlapping shingles: [String]
  ) {
    fingerprints.removeAll {
      ($0.label == .junk) != (label == .junk)
        && CampaignContent.overlap($0.shingles, shingles) >= CampaignContent.minimumOverlap
    }
  }

  private mutating func withdrawJunkPredictions(coveredBy sample: LearningSample) {
    let tokens = Set(sample.tokens)
    samples.removeAll {
      $0.provenance == .highConfidencePrediction && $0.label == .junk
        && Set($0.tokens).isSubset(of: tokens)
    }
  }

  private mutating func enforceBounds() {
    var sampleIDs: Set<String> = []
    samples = samples.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
      .filter { sampleIDs.insert($0.id).inserted }.prefix(maximumSamples).map { $0 }
    var fingerprintIDs: Set<String> = []
    fingerprints = fingerprints.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
      .filter { fingerprintIDs.insert($0.id).inserted }.prefix(maximumFingerprints).map { $0 }
  }

  private enum CodingKeys: String, CodingKey {
    case samples, fingerprints, maximumSamples, maximumFingerprints
  }
}

extension LearningSample {
  static func make(
    message: ParsedMessage,
    evidence: EvidenceBundle,
    label: MailLabel,
    provenance: LearningProvenance,
    id: String? = nil,
    date: Date
  ) -> LearningSample {
    LearningSample(
      id: id ?? identity(for: message),
      date: date,
      label: label,
      provenance: provenance,
      tokens: tokens(for: message),
      features: LearningFeatures(evidence)
    )
  }

  /// Selects the bounded token sample shared by training and inference.
  static func tokens(for message: ParsedMessage) -> [String] {
    LearningText.hashSample(message.subject + " " + message.text, limit: maximumTokens)
  }

  /// Returns the deterministic content split that offline evaluation uses to select reviewed labels.
  public static func partition(for id: String) -> LearningPartition {
    (UInt8(id.prefix(partitionPrefixCharacters), radix: 16) ?? 0)
      .isMultiple(of: heldOutPartitionDivisor) ? .heldOut : .training
  }
}

extension LearningSample {
  var isValid: Bool {
    id.count == Self.hashCharacters && tokens.count <= Self.maximumTokens
      && tokens.allSatisfy { $0.count <= Self.maximumTokenCharacters } && features.isValid
      && date.timeIntervalSince1970.isFinite
  }
}

extension CampaignFingerprint {
  private static let maximumAnchors = 21
  private static let maximumAnchorCharacters = 260
  private static let maximumShingles = 128

  var isValid: Bool {
    id.count == LearningSample.hashCharacters && anchors.count <= Self.maximumAnchors
      && anchors.allSatisfy { $0.count <= Self.maximumAnchorCharacters }
      && shingles.count <= Self.maximumShingles
      && shingles.allSatisfy { $0.count == LearningSample.hashCharacters }
      && date.timeIntervalSince1970.isFinite
  }

  /// This signature under the identity of the sample it was recorded with.
  fileprivate func identified(as id: String) -> Self {
    Self(id: id, date: date, label: label, anchors: anchors, shingles: shingles)
  }
}
