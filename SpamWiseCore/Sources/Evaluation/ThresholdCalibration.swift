public import SpamWiseCore

/**
 Cumulative model precision and whole-cohort policy metrics at one Junk confidence threshold,
 with the graymail category threshold held at ``ThresholdCalibration/graymailThreshold``.
 */
public struct ThresholdPoint: Codable, Sendable {
  /// The minimum confidence for a Junk action.
  public var threshold: Int
  /// Binary-labeled model Junk verdicts at or above the threshold.
  public var modelJunkVerdicts: Int
  /// Fraction of those verdicts that were actually junk; nil when there were none.
  public var cumulativePrecision: Double?
  /// Whole-cohort metrics with `Decision` applied at this threshold, including the
  /// false-positive upper bound.
  public var metrics: BinaryMetrics

  init(threshold: Int, graymailThreshold: Int, observations: [EvaluationObservation]) {
    let verdicts = observations.filter {
      $0.path == .model && $0.truth != .graymail && $0.modelLabel == .junk
        && ($0.confidence ?? Int.min) >= threshold
    }
    self.threshold = threshold
    modelJunkVerdicts = verdicts.count
    cumulativePrecision =
      verdicts.isEmpty
      ? nil : Double(verdicts.filter { $0.truth == .junk }.count) / Double(verdicts.count)
    metrics = BinaryMetrics(
      observations.map {
        $0.decided(junkThreshold: threshold, graymailThreshold: graymailThreshold)
      }
    )
  }
}

/// A data-derived threshold for one filtering strength, selected on training data and checked
/// on held-out data.
public struct StrengthCalibration: Codable, Sendable {
  /// The strength being calibrated.
  public var strength: FilteringStrength
  /// The strength's current provisional threshold.
  public var currentThreshold: Int
  /// Whole-cohort metrics at the current threshold.
  public var current: BinaryMetrics
  /// Highest acceptable one-sided 95% upper bound on the good-mail false-positive rate.
  public var falsePositiveTarget: Double
  /// Lowest threshold whose training false-positive bound meets the target; nil when none does.
  public var selectedThreshold: Int?
  /// Training-split metrics at the selected threshold.
  public var training: BinaryMetrics?
  /// Held-out metrics at the selected threshold.
  public var heldOut: BinaryMetrics?
  /// Whether the held-out false-positive bound also meets the target.
  public var validated: Bool
}

/// Per-point threshold metrics and data-derived strength thresholds.
public struct ThresholdCalibration: Codable, Sendable {
  /// Junk confidence thresholds reported and considered for selection.
  public static let thresholds = 85...100
  private static let conservativeFalsePositiveTarget = 0.001
  private static let balancedFalsePositiveTarget = 0.002
  private static let aggressiveFalsePositiveTarget = 0.005
  private static let ruleOfThreeErrors = 3.0
  /// The category confidence that moves graymail the user chose Junk for, throughout ``curve``.
  public var graymailThreshold: Int
  /// Metrics at each threshold across every observation.
  public var curve: [ThresholdPoint]
  /// The current and selected threshold for each strength.
  public var strengths: [StrengthCalibration]

  /**
   Scores every threshold, then selects each strength's threshold on the training partition and
   validates it on the held-out partition.

   Observations without a partition contribute only to ``curve`` and the current-threshold
   metrics. Each strength's selection holds the graymail category threshold at that strength's.

   - Parameter strength: The strength whose graymail category threshold ``curve`` holds.
   */
  public init(observations: [EvaluationObservation], strength: FilteringStrength = .balanced) {
    let training = observations.filter { $0.partition == .training }
    let heldOut = observations.filter { $0.partition == .heldOut }
    graymailThreshold = strength.graymailThreshold
    curve = Self.thresholds.map { [graymailThreshold] in
      ThresholdPoint(
        threshold: $0,
        graymailThreshold: graymailThreshold,
        observations: observations
      )
    }
    strengths = FilteringStrength.allCases.map { strength in
      Self.calibrate(strength, all: observations, training: training, heldOut: heldOut)
    }
  }

  /// Fewest good examples whose rule-of-three bound, with zero false positives, meets the
  /// target for `strength`.
  public static func minimumGoodExamples(for strength: FilteringStrength) -> Int {
    Int((ruleOfThreeErrors / falsePositiveTarget(for: strength)).rounded(.up))
  }

  /// Highest acceptable one-sided 95% false-positive upper bound for `strength`.
  public static func falsePositiveTarget(for strength: FilteringStrength) -> Double {
    switch strength {
      case .conservative: conservativeFalsePositiveTarget
      case .balanced: balancedFalsePositiveTarget
      case .aggressive: aggressiveFalsePositiveTarget
    }
  }

  private static func calibrate(
    _ strength: FilteringStrength,
    all: [EvaluationObservation],
    training: [EvaluationObservation],
    heldOut: [EvaluationObservation]
  ) -> StrengthCalibration {
    let target = falsePositiveTarget(for: strength)
    let selected = thresholds.first { threshold in
      meets(target, metrics(training, junkThreshold: threshold, strength: strength))
    }
    let validation = selected.map { metrics(heldOut, junkThreshold: $0, strength: strength) }
    return StrengthCalibration(
      strength: strength,
      currentThreshold: strength.threshold,
      current: BinaryMetrics(all.map { $0.decided(strength: strength) }),
      falsePositiveTarget: target,
      selectedThreshold: selected,
      training: selected.map { metrics(training, junkThreshold: $0, strength: strength) },
      heldOut: validation,
      validated: validation.map { meets(target, $0) } ?? false
    )
  }

  private static func metrics(
    _ rows: [EvaluationObservation],
    junkThreshold: Int,
    strength: FilteringStrength
  ) -> BinaryMetrics {
    BinaryMetrics(
      rows.map {
        $0.decided(junkThreshold: junkThreshold, graymailThreshold: strength.graymailThreshold)
      }
    )
  }

  private static func meets(_ target: Double, _ metrics: BinaryMetrics) -> Bool {
    metrics.falsePositiveUpper95.map { $0 <= target } ?? false
  }
}
