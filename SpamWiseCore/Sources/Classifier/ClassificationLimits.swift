import Foundation

/// Bounds on what one classification request carries.
public enum ClassificationLimits {
  static let maximumResponseTokens = 1024
  static let maximumReasonCharacters = 240
  static let confidenceRange = 0...100
  static let timeoutRange: ClosedRange<TimeInterval> = 0.01...15
  /// Similar corrections a request may quote.
  public static let correctionLimitRange = 0...20
  /// Estimated tokens of message body a request may carry.
  public static let bodyTokenBudgetRange = 100...4000
  /// Characters of filtering policy a request quotes; longer policies are truncated.
  public static let maximumPolicyCharacters = 4000
  static let maximumSubjectCharacters = 500
  static let charactersPerToken = 4
  static let maximumInputTokens = 1_000_000
  static let maximumOutputTokens = 100_000
}

extension ClosedRange {
  /// Returns `value` limited to this range.
  func clamp(_ value: Bound) -> Bound { Swift.min(upperBound, Swift.max(lowerBound, value)) }
}
