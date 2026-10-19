import Foundation
public import SpamWiseCore

/// Human labels; graymail is excluded from binary good/junk statistics.
public enum EvaluationTruth: String, Codable, Sendable, CaseIterable { case good, junk, graymail }

/// One corpus result, including failures rather than silently discarding them.
public struct EvaluationObservation: Codable, Sendable {
  /// Relative corpus path, never the message body.
  public var file: String
  /// Independently supplied human label.
  public var truth: EvaluationTruth
  /// Effective decision label after applying the selected threshold.
  public var label: MailLabel?
  /// Original model label used for confidence calibration before policy thresholds.
  public var modelLabel: MailLabel?
  /// Uncalibrated model confidence, absent for failures.
  public var confidence: Int?
  /// What decided the message; nil for results supplied by another system.
  public var path: DecisionPath?
  /// Whether part of the message couldn't be read reliably, which keeps an Inbox verdict in Review.
  public var concealsContent: Bool
  /// Statistical split used to select thresholds; nil when the source assigns none.
  public var partition: LearningPartition?
  /// Explanation retained for misclassification review.
  public var reason: String
  /**
   Records one independently labeled result.

   - Parameters:
     - file: Relative corpus path or sample identifier.
     - truth: The human label.
     - label: The effective decision label, or nil when unclassified.
     - confidence: The verdict's confidence, or nil without a verdict.
     - path: What decided the message.
     - reason: Explanation retained for misclassification review.
     - modelLabel: The verdict's label; defaults to `label`.
     - concealsContent: Whether policy kept an Inbox verdict in Review for unreadable content.
     - partition: The statistical split, when the source assigns one.
   */
  public init(
    file: String,
    truth: EvaluationTruth,
    label: MailLabel?,
    confidence: Int?,
    path: DecisionPath?,
    reason: String,
    modelLabel: MailLabel? = nil,
    concealsContent: Bool = false,
    partition: LearningPartition? = nil
  ) {
    self.file = file; self.truth = truth; self.label = label; self.confidence = confidence
    self.path = path; self.reason = reason; self.modelLabel = modelLabel ?? label
    self.concealsContent = concealsContent; self.partition = partition
  }

  /// Records the pipeline's persisted result for one labeled message.
  public init(
    file: String,
    truth: EvaluationTruth,
    partition: LearningPartition?,
    record: DecisionRecord
  ) {
    self.init(
      file: file,
      truth: truth,
      label: record.decision.label,
      confidence: record.verdict?.confidence,
      path: record.path,
      reason: record.decision.reason.diagnosticDescription,
      modelLabel: record.verdict?.label,
      concealsContent: record.decision.reason == .concealedContent,
      partition: partition
    )
  }

  /// This result as `Decision` would label it at `strength`; results without a verdict are unchanged.
  public func decided(strength: FilteringStrength) -> Self {
    decided { verdict in
      try Decision.evaluate(verdict, strength: strength, concealsContent: concealsContent)
    }
  }

  /// This result as `Decision` would label it at an explicit Junk confidence threshold.
  public func decided(junkThreshold: Int) -> Self {
    decided { verdict in
      try Decision.evaluate(verdict, junkThreshold: junkThreshold, concealsContent: concealsContent)
    }
  }

  private func decided(by policy: (Verdict) throws -> Decision) -> Self {
    guard let modelLabel, let confidence,
      let decision = try? policy(Verdict(label: modelLabel, confidence: confidence, reason: reason))
    else { return self }
    var row = self
    row.label = decision.label
    return row
  }
}

/// Binary Junk metrics; Review and unclassified results are not automatically junked.
public struct BinaryMetrics: Codable, Sendable {
  /// Number of human-labeled good examples, including classification failures.
  public var good: Int
  /// Number of human-labeled junk examples.
  public var junk: Int
  /// Good messages assigned Junk.
  public var falsePositives: Int
  /// Junk messages assigned Junk.
  public var truePositives: Int
  /// Good messages retained outside Junk, including fail-open errors.
  public var trueNegatives: Int
  /// Junk messages retained outside Junk, including Review and errors.
  public var falseNegatives: Int
  /// Fraction of Junk decisions that were actually junk; nil when none were made.
  public var junkPrecision: Double?
  /// Fraction of labeled junk assigned Junk; failures count as missed junk.
  public var junkRecall: Double?
  /// One-sided exact binomial upper bound; nil without good examples.
  public var falsePositiveUpper95: Double?
  /// Rule-of-three approximation for zero false positives only.
  public var ruleOfThreeUpper95: Double?

  /// Counts binary outcomes, excluding graymail.
  public init(_ rows: [EvaluationObservation]) {
    let binary = rows.filter { $0.truth != .graymail }
    good = binary.filter { $0.truth == .good }.count
    junk = binary.filter { $0.truth == .junk }.count
    falsePositives = binary.filter { $0.truth == .good && $0.label == .junk }.count
    truePositives = binary.filter { $0.truth == .junk && $0.label == .junk }.count
    trueNegatives = good - falsePositives
    falseNegatives = junk - truePositives
    let positives = truePositives + falsePositives
    junkPrecision = positives > 0 ? Double(truePositives) / Double(positives) : nil
    junkRecall = junk > 0 ? Double(truePositives) / Double(junk) : nil
    falsePositiveUpper95 = BinomialBound.upper95(errors: falsePositives, trials: good)
    ruleOfThreeUpper95 = falsePositives == 0 && good > 0 ? min(1, 3 / Double(good)) : nil
  }
}

/// Recomputed metrics with deterministic gates kept separate from the model by decision path.
public struct EvaluationReport: Codable, Sendable {
  /// Confusion matrix indexed by true label then effective label or unclassified.
  public var confusion: [String: [String: Int]]
  /// Overall binary good/junk metrics.
  public var binary: BinaryMetrics
  /// Binary metrics split by decision source; results supplied by another system have none.
  public var perPath: [DecisionPath: BinaryMetrics]
  /// Number of inputs with no classification result.
  public var unclassified: Int
  /// Every result that differs from the expected label, including classification failures.
  public var misclassifications: [EvaluationObservation]
  /// Builds all metrics from independently labeled observations.
  public init(observations: [EvaluationObservation]) {
    confusion = [:]
    for row in observations {
      confusion[row.truth.rawValue, default: [:]][
        row.label?.rawValue ?? "unclassified",
        default: 0
      ] += 1
    }
    binary = BinaryMetrics(observations)
    perPath = observations.reduce(into: [DecisionPath: [EvaluationObservation]]()) { groups, row in
      if let path = row.path { groups[path, default: []].append(row) }
    }.mapValues(BinaryMetrics.init)
    unclassified = observations.filter { $0.label == nil }.count
    misclassifications = observations.filter {
      let expected: MailLabel = $0.truth == .good ? .inbox : $0.truth == .junk ? .junk : .review
      return $0.label != expected
    }
  }
}
