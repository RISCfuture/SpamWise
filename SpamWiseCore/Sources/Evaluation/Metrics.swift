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
  /// Gate, model, or error source.
  public var path: String
  /// Explanation retained for misclassification review.
  public var reason: String
  /// Records one independently labeled result.
  public init(
    file: String,
    truth: EvaluationTruth,
    label: MailLabel?,
    confidence: Int?,
    path: String,
    reason: String,
    modelLabel: MailLabel? = nil
  ) {
    self.file = file; self.truth = truth; self.label = label; self.confidence = confidence
    self.path = path; self.reason = reason; self.modelLabel = modelLabel ?? label
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

  init(_ rows: [EvaluationObservation]) {
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

/// Precision observed among model Junk decisions in one stated-confidence range.
public struct CalibrationBucket: Codable, Sendable {
  /// Inclusive lower bound of the confidence bucket.
  public var lower: Int
  /// Inclusive upper bound of the confidence bucket.
  public var upper: Int
  /// Number of binary-labeled model Junk decisions in this bucket.
  public var count: Int
  /// Observed Junk precision; nil for an empty bucket.
  public var precision: Double?
}

/// Recomputed metrics with model calibration kept separate from deterministic gates.
public struct EvaluationReport: Codable, Sendable {
  /// Confusion matrix indexed by true label then effective label or unclassified.
  public var confusion: [String: [String: Int]]
  /// Overall binary good/junk metrics.
  public var binary: BinaryMetrics
  /// Binary metrics split by decision source.
  public var perPath: [String: BinaryMetrics]
  /// Model Junk precision buckets, excluding gates and graymail.
  public var calibration: [CalibrationBucket]
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
    perPath = Dictionary(grouping: observations, by: \.path).mapValues(BinaryMetrics.init)
    unclassified = observations.filter { $0.label == nil }.count
    misclassifications = observations.filter {
      let expected: MailLabel = $0.truth == .good ? .inbox : $0.truth == .junk ? .junk : .review
      return $0.label != expected
    }
    calibration = stride(from: 0, through: 90, by: 10).map { lower in
      let upper = lower == 90 ? 100 : lower + 9
      let rows = observations.filter {
        $0.path == "model" && $0.truth != .graymail && $0.modelLabel == .junk
          && (lower...upper).contains($0.confidence ?? -1)
      }
      return CalibrationBucket(
        lower: lower,
        upper: upper,
        count: rows.count,
        precision: rows.isEmpty
          ? nil : Double(rows.filter { $0.truth == .junk }.count) / Double(rows.count)
      )
    }
  }
}

/// One-sided Clopper-Pearson 95% upper confidence bounds for a binomial error rate.
public enum BinomialBound {
  private static let upperTailProbability = 0.05
  private static let bisectionIterations = 70
  /// Returns nil for an empty sample; zero-error samples use the exact closed form.
  public static func upper95(errors: Int, trials: Int) -> Double? {
    guard trials > 0, (0...trials).contains(errors) else { return nil }
    if errors == trials { return 1 }
    if errors == 0 { return 1 - pow(upperTailProbability, 1 / Double(trials)) }
    var low = Double(errors) / Double(trials), high = 1.0
    for _ in 0..<bisectionIterations {
      let probability = (low + high) / 2
      if cumulative(errors: errors, trials: trials, probability: probability) > upperTailProbability
      {
        low = probability
      } else {
        high = probability
      }
    }
    return high
  }
  private static func cumulative(errors: Int, trials: Int, probability: Double) -> Double {
    var term = Double(trials) * log1p(-probability)
    var terms = [term]
    for index in 1...errors {
      term +=
        log(Double(trials - index + 1)) - log(Double(index)) + log(probability)
        - log1p(-probability)
      terms.append(term)
    }
    let peak = terms.max() ?? 0
    return exp(peak) * terms.reduce(0) { $0 + exp($1 - peak) }
  }
}
