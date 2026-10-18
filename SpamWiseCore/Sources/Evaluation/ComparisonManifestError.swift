public import Foundation

/// Comparison manifest validation failures; no provider or Mail operation is performed.
public enum ComparisonManifestError: CorpusEvaluationError, BoundedInputError, Sendable, Equatable,
  LocalizedError
{
  /// The manifest declares a schema version this build can't read.
  case unsupportedSchema(Int)
  /// The manifest doesn't attest that a human reviewed every truth label.
  case notHumanReviewed
  /// The manifest has no holdout identifier.
  case missingHoldoutID
  /// The cohort has too few or too many messages.
  case messageCount(Int, allowed: ClosedRange<Int>)
  /// A message has a blank identifier.
  case blankMessageID
  /// A message has a blank campaign.
  case blankCampaign(messageID: String)
  /// Two messages share an identifier.
  case duplicateMessage(String)
  /// Two messages share a campaign, so the cohort isn't campaign-disjoint.
  case duplicateCampaign(String)
  /// A holdout campaign also appears among the training campaigns.
  case trainingCampaign(String)
  /// The manifest has too few or too many runs.
  case runCount(Int, allowed: ClosedRange<Int>)
  /// A run has a blank system name.
  case blankSystem
  /// Two runs share a system name.
  case duplicateSystem(String)
  /// A run has a blank configuration identifier.
  case blankConfigurationID(system: String)
  /// A run doesn't attest that learning was frozen.
  case learningNotFrozen(system: String)
  /// A run reports one message more than once.
  case duplicateResult(system: String, messageID: String)
  /// A run reports a message outside the cohort.
  case unknownResult(system: String, messageID: String)
  /// A run omits a cohort message.
  case missingResult(system: String, messageID: String)
  /// A run reports a negative or infinite measurement, or a nonpositive elapsed time.
  case invalidMeasurement(system: String, field: String)
  /// A run reports a charge without saying whether it was measured or estimated.
  case missingCostBasis(system: String)
  /// The manifest data is larger than the report accepts.
  case manifestTooLarge(limit: Int)
  /// The manifest path names a directory or other non-regular file.
  case notRegularFile(URL)
  /// The manifest file is larger than the report accepts.
  case fileTooLarge(URL, limit: Int)

  /// General description of the failed comparison.
  public var errorDescription: String? { String(localized: "Couldn’t compare the frozen runs.") }
  /// The manifest condition that prevents a valid comparison.
  public var failureReason: String? {
    headerReason ?? cohortReason ?? runReason ?? inputReason
  }
  /// The correction to make to the manifest.
  public var recoverySuggestion: String? {
    switch self {
      case .duplicateCampaign, .trainingCampaign:
        String(
          localized: "Keep one message per campaign, and none from a campaign used in training."
        )
      case .missingResult:
        String(localized: "Record every message in every run, using a null label to abstain.")
      case .missingCostBasis: String(localized: "Set costBasis to measured or estimated.")
      case .learningNotFrozen:
        String(localized: "Freeze learning before the run, then set learningFrozen to true.")
      case .manifestTooLarge, .fileTooLarge:
        String(localized: "Compare fewer messages or runs in each manifest.")
      default: nil
    }
  }

  private var headerReason: String? {
    switch self {
      case .unsupportedSchema(let schema):
        String(localized: "Manifest schema \(schema, format: .number) isn’t supported.")
      case .notHumanReviewed: String(localized: "The manifest doesn’t attest human review.")
      case .missingHoldoutID: String(localized: "The manifest has no holdout ID.")
      default: nil
    }
  }

  private var cohortReason: String? {
    switch self {
      case let .messageCount(count, allowed):
        String(
          localized:
            "The cohort has \(count, format: .number) messages; \(allowed.lowerBound, format: .number) to \(allowed.upperBound, format: .number) are supported."
        )
      case .blankMessageID: String(localized: "A message has a blank ID.")
      case .blankCampaign(let id): String(localized: "Message \(id) has a blank campaign.")
      case .duplicateMessage(let id): String(localized: "Message \(id) appears more than once.")
      case .duplicateCampaign(let campaign):
        String(localized: "Campaign \(campaign) appears in more than one message.")
      case .trainingCampaign(let campaign):
        String(localized: "Campaign \(campaign) is also a training campaign.")
      default: nil
    }
  }

  private var runReason: String? {
    switch self {
      case let .runCount(count, allowed):
        String(
          localized:
            "The manifest has \(count, format: .number) runs; \(allowed.lowerBound, format: .number) to \(allowed.upperBound, format: .number) are supported."
        )
      case .blankSystem: String(localized: "A run has a blank system name.")
      case .duplicateSystem(let system):
        String(localized: "System \(system) appears in more than one run.")
      case .blankConfigurationID(let system):
        String(localized: "System \(system) has a blank configuration ID.")
      case .learningNotFrozen(let system):
        String(localized: "System \(system) doesn’t attest frozen learning.")
      case let .duplicateResult(system, id):
        String(localized: "System \(system) reports message \(id) more than once.")
      case let .unknownResult(system, id):
        String(localized: "System \(system) reports message \(id), which isn’t in the cohort.")
      case let .missingResult(system, id):
        String(localized: "System \(system) has no result for message \(id).")
      case let .invalidMeasurement(system, field):
        String(localized: "System \(system) reports an invalid \(field).")
      case .missingCostBasis(let system):
        String(localized: "System \(system) reports a cost without a costBasis.")
      default: nil
    }
  }

  private var inputReason: String? {
    switch self {
      case .manifestTooLarge(let limit):
        String(
          localized: "The manifest exceeds the \(limit.formatted(.byteCount(style: .file))) limit."
        )
      case .notRegularFile(let url): String(localized: "\(url.path) isn’t a regular file.")
      case let .fileTooLarge(url, limit):
        String(
          localized:
            "\(url.path) exceeds the \(limit.formatted(.byteCount(style: .file))) manifest limit."
        )
      default: nil
    }
  }
}
