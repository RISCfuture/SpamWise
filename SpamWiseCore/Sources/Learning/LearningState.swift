public import Classifier
public import Foundation
public import MessageModel
public import Signals

/// Persisted sample partition; held-out labels never train either estimator.
public enum LearningPartition: String, Codable, Sendable {
  /// Eligible for model fitting when the provenance permits it.
  case training
  /// Reserved for evaluation and excluded from model fitting.
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
  private static let maximumIdentityCharacters = 8000
  private static let maximumTokens = 128
  private static let partitionPrefixCharacters = 2
  private static let heldOutPartitionDivisor: UInt8 = 5
  /// Content-based identity used to prevent duplicate training and partition leakage.
  public let id: String
  /// Date the latest label was recorded.
  public let date: Date
  /// Latest accepted label.
  public let label: MailLabel
  /// Whether a user or classifier supplied the label.
  public let provenance: LearningProvenance
  /// Stable content-hash split shared by duplicate messages.
  public let partition: LearningPartition
  /// Bounded lexical features.
  public let tokens: [String]
  /// Version-one bounded numeric features in a fixed order.
  public let features: [Double]
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
  /// Inbox signatures suppress similar learned Junk campaigns.
  public let label: MailLabel
  /// Sender and link-domain anchors needed in addition to matching content.
  public let anchors: [String]
  /// Bounded hashes of meaningful consecutive word sequences.
  public let shingles: [String]
}

/// An anchored explicit-Junk campaign match, never a standalone action instruction.
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
  /// Explicit binary corrections reserved for evaluation.
  public var heldOutCount: Int
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
  private static let hashCharacters = 64
  private static let maximumSampleTokens = 128
  private static let maximumTokenCharacters = 40
  private static let maximumAnchors = 21
  private static let maximumAnchorCharacters = 260
  private static let maximumShingles = 128
  /// Latest bounded labels, ordered newest first with a stable identity tie break.
  public private(set) var samples: [LearningSample] = []
  /// Explicit campaign examples and Good suppressions.
  public private(set) var fingerprints: [CampaignFingerprint] = []
  /// Maximum retained examples, capped at 10,000.
  public let maximumSamples: Int
  /// Maximum retained campaign signatures, capped at 1,000.
  public let maximumFingerprints: Int
  /// Explicit binary training examples; predictions and held-out data are excluded.
  public var trainingSamples: [LearningSample] {
    samples.filter {
      $0.partition == .training && $0.provenance == .explicitCorrection && $0.label != .review
    }
  }

  /// Creates empty state with bounded retention limits.
  public init(maximumSamples: Int = 10000, maximumFingerprints: Int = 1000) {
    self.maximumSamples = min(Self.sampleLimit, max(1, maximumSamples))
    self.maximumFingerprints = min(Self.fingerprintLimit, max(1, maximumFingerprints))
  }

  /// Decodes older empty state and clamps persisted retention and feature bounds.
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
    samples = samples.filter {
      $0.id.count == Self.hashCharacters && $0.tokens.count <= Self.maximumSampleTokens
        && $0.tokens.allSatisfy { $0.count <= Self.maximumTokenCharacters }
        && $0.features.count == StatisticalLearning.featureCount
        && $0.features.allSatisfy { $0.isFinite && (0...1).contains($0) }
        && $0.partition == LearningSample.partition(for: $0.id)
        && $0.date.timeIntervalSince1970.isFinite
    }
    fingerprints = fingerprints.filter {
      $0.id.count == Self.hashCharacters && $0.anchors.count <= Self.maximumAnchors
        && $0.anchors.allSatisfy { $0.count <= Self.maximumAnchorCharacters }
        && $0.shingles.count <= Self.maximumShingles
        && $0.shingles.allSatisfy { $0.count == Self.hashCharacters }
        && $0.date.timeIntervalSince1970.isFinite
    }
    enforceBounds()
  }

  /// Stores an explicit correction, replacing the same content's prior label and campaign evidence.
  public mutating func recordCorrection(
    message: ParsedMessage,
    evidence: EvidenceBundle,
    label: MailLabel,
    date: Date = .now
  ) {
    let sample = LearningSample.make(
      message: message,
      evidence: evidence,
      label: label,
      provenance: .explicitCorrection,
      date: date
    )
    samples.removeAll { $0.id == sample.id }
    samples.append(sample)
    fingerprints.removeAll { $0.id == sample.id }
    if let signature = CampaignContent.fingerprint(message: message, label: label, date: date) {
      if label != .junk {
        fingerprints.removeAll {
          $0.label == .junk
            && CampaignContent.overlap($0.shingles, signature.shingles)
              >= CampaignContent.minimumOverlap
        }
        let invalidated = Set(
          samples.filter { $0.provenance == .highConfidencePrediction && $0.label == .junk }.map(
            \.id
          )
        )
        samples.removeAll {
          invalidated.contains($0.id) && Set($0.tokens).isSubset(of: Set(sample.tokens))
        }
      }
      fingerprints.append(signature)
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

  /// Returns an anchored near-duplicate campaign after applying explicit Good suppressions.
  public func campaignMatch(for message: ParsedMessage) -> CampaignMatch? {
    CampaignContent.match(message: message, fingerprints: fingerprints)
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
        partition: sample.partition,
        tokens: sample.tokens,
        features: sample.features
      )
    )
    enforceBounds()
  }

  /// Computes bounded statistical estimates only after minimum reviewed-data gates pass.
  public func estimate(message: ParsedMessage, evidence: EvidenceBundle) -> LearningEstimate {
    let reviewed = trainingSamples
    let predictions = samples.filter {
      $0.provenance == .highConfidencePrediction && $0.partition == .training
    }
    return LearningEstimate(
      bayesLogOdds: StatisticalLearning.bayes(
        message: message,
        reviewed: reviewed,
        predictions: predictions
      ),
      logisticMargin: StatisticalLearning.logistic(evidence: evidence, reviewed: reviewed),
      trainingCount: reviewed.count,
      heldOutCount: samples.filter {
        $0.partition == .heldOut && $0.provenance == .explicitCorrection && $0.label != .review
      }.count
    )
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
    date: Date
  ) -> LearningSample {
    let id = identity(for: message)
    return LearningSample(
      id: id,
      date: date,
      label: label,
      provenance: provenance,
      partition: partition(for: id),
      tokens: Array(Set(LearningText.tokens(message.subject + " " + message.text))).sorted().prefix(
        maximumTokens
      ).map { $0 },
      features: StatisticalLearning.features(evidence)
    )
  }

  /// Returns the deterministic content split used by learning and reviewed-corpus evaluation.
  public static func partition(for id: String) -> LearningPartition {
    (UInt8(id.prefix(partitionPrefixCharacters), radix: 16) ?? 0)
      .isMultiple(of: heldOutPartitionDivisor) ? .heldOut : .training
  }
}
