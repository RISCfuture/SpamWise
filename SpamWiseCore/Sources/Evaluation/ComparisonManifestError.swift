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
  public var errorDescription: String? {
    String(localized: "Couldn’t compare the frozen runs.", bundle: .module)
  }
  /// The manifest condition that prevents a valid comparison.
  public var failureReason: String? {
    headerReason ?? cohortReason ?? runReason ?? inputReason
  }
  /// The correction to make to the manifest.
  public var recoverySuggestion: String? {
    switch self {
      case .duplicateCampaign, .trainingCampaign:
        String(
          localized: "Keep one message per campaign, and none from a campaign used in training.",
          bundle: .module
        )
      case .missingResult:
        String(
          localized: "Record every message in every run, using a null label to abstain.",
          bundle: .module
        )
      case .missingCostBasis:
        String(localized: "Set costBasis to measured or estimated.", bundle: .module)
      case .learningNotFrozen:
        String(
          localized: "Freeze learning before the run, then set learningFrozen to true.",
          bundle: .module
        )
      case .manifestTooLarge, .fileTooLarge:
        String(localized: "Compare fewer messages or runs in each manifest.", bundle: .module)
      default: nil
    }
  }

  private var headerReason: String? {
    switch self {
      case .unsupportedSchema(let schema):
        String(
          localized: "Manifest schema \(schema, format: .number) isn’t supported.",
          bundle: .module
        )
      case .notHumanReviewed:
        String(localized: "The manifest doesn’t attest human review.", bundle: .module)
      case .missingHoldoutID: String(localized: "The manifest has no holdout ID.", bundle: .module)
      default: nil
    }
  }

  private var cohortReason: String? {
    switch self {
      case let .messageCount(count, allowed):
        String(
          localized:
            "The cohort has \(count) messages; \(allowed.lowerBound) to \(allowed.upperBound) are supported.",
          bundle: .module
        )
      case .blankMessageID: String(localized: "A message has a blank ID.", bundle: .module)
      case .blankCampaign(let id):
        String(localized: "Message \(id) has a blank campaign.", bundle: .module)
      case .duplicateMessage(let id):
        String(localized: "Message \(id) appears more than once.", bundle: .module)
      case .duplicateCampaign(let campaign):
        String(localized: "Campaign \(campaign) appears in more than one message.", bundle: .module)
      case .trainingCampaign(let campaign):
        String(localized: "Campaign \(campaign) is also a training campaign.", bundle: .module)
      default: nil
    }
  }

  private var runReason: String? {
    switch self {
      case let .runCount(count, allowed):
        String(
          localized:
            "The manifest has \(count) runs; \(allowed.lowerBound) to \(allowed.upperBound) are supported.",
          bundle: .module
        )
      case .blankSystem: String(localized: "A run has a blank system name.", bundle: .module)
      case .duplicateSystem(let system):
        String(localized: "System \(system) appears in more than one run.", bundle: .module)
      case .blankConfigurationID(let system):
        String(localized: "System \(system) has a blank configuration ID.", bundle: .module)
      case .learningNotFrozen(let system):
        String(localized: "System \(system) doesn’t attest frozen learning.", bundle: .module)
      case let .duplicateResult(system, id):
        String(localized: "System \(system) reports message \(id) more than once.", bundle: .module)
      case let .unknownResult(system, id):
        String(
          localized: "System \(system) reports message \(id), which isn’t in the cohort.",
          bundle: .module
        )
      case let .missingResult(system, id):
        String(localized: "System \(system) has no result for message \(id).", bundle: .module)
      case let .invalidMeasurement(system, field):
        String(localized: "System \(system) reports an invalid \(field).", bundle: .module)
      case .missingCostBasis(let system):
        String(localized: "System \(system) reports a cost without a costBasis.", bundle: .module)
      default: nil
    }
  }

  private var inputReason: String? {
    switch self {
      case .manifestTooLarge(let limit):
        String(
          localized: "The manifest exceeds the \(limit.formatted(.byteCount(style: .file))) limit.",
          bundle: .module
        )
      case .notRegularFile(let url):
        String(localized: "\(url.path) isn’t a regular file.", bundle: .module)
      case let .fileTooLarge(url, limit):
        String(
          localized:
            "\(url.path) exceeds the \(limit.formatted(.byteCount(style: .file))) manifest limit.",
          bundle: .module
        )
      default: nil
    }
  }
}
