import Foundation

enum ClassificationLimits {
  static let maximumResponseTokens = 1024
  static let maximumReasonCharacters = 240
  static let confidenceRange = 0...100
  static let timeoutRange: ClosedRange<TimeInterval> = 0.01...15
  static let correctionLimitRange = 0...100
  static let bodyTokenBudgetRange = 100...4000
  static let maximumPolicyCharacters = 4000
  static let maximumSubjectCharacters = 500
  static let charactersPerToken = 4
  static let maximumInputTokens = 1_000_000
  static let maximumOutputTokens = 100_000
}
