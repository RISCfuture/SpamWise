import Foundation
public import Classifier

/// Provisional confidence thresholds, pending held-out calibration.
public enum FilteringStrength: String, Codable, Sendable, CaseIterable {
  /// Requires confidence of at least 99 before a Junk action.
  case conservative
  /// Requires confidence of at least 95 before a Junk action.
  case balanced
  /// Requires confidence of at least 90 before a Junk action.
  case aggressive
  /// Minimum provisional confidence required to act on a Junk verdict.
  public var threshold: Int {
    switch self { case .conservative: 99;  case .balanced: 95;  case .aggressive: 90
    }
  }
}
/// The annotation applied to Review messages left in Inbox.
public enum ReviewTreatment: String, Codable, Sendable, CaseIterable {
  /// Marks Review messages with an orange flag.
  case orangeFlag
  /// Marks Review messages with an orange background.
  case orangeBackground
}
/// The supported action vocabulary deliberately contains no deletion or Trash operation.
public enum MailAction: String, Codable, Sendable {
  /// Leaves the message unchanged.
  case none
  /// Applies the orange Review flag.
  case orangeFlag
  /// Applies the orange Review background.
  case orangeBackground
  /// Moves the message into the account’s Junk mailbox.
  case moveToJunk
  /// Moves the message into the account’s Inbox.
  case moveToInbox
}
/// Observed dispatch state, independent of the model verdict.
public enum ActionOutcome: String, Codable, Sendable {
  /// The decision requires no mail operation.
  case noAction
  /// Dry run suppressed the intended operation.
  case dryRun
  /// The user paused filtering.
  case paused
  /// The decision is persisted and awaits dispatch evaluation.
  case pending
  /// Dispatch was requested without confirmed completion.
  case requested
  /// The adapter observed the intended client state.
  case applied
  /// The requested operation failed.
  case failed
  /// No valid classification was produced.
  case unclassified
  /// A newer policy revision invalidated this decision.
  case superseded
  /// An existing action claim or in-flight operation suppressed duplicate work.
  case duplicate
  /// No validated integration could perform the action.
  case integrationUnavailable
}
/// An intended label and supported mail action.
public struct Decision: Codable, Sendable, Equatable {
  /// Inbox, Review, or Junk; absent when unclassified.
  public var label: MailLabel?
  /// The intended supported Mail operation.
  public var action: MailAction
  /// Short explanation of the evidence or policy behind this result.
  public var reason: String
  /// Creates a Decision with the supplied configuration.
  public init(label: MailLabel?, action: MailAction, reason: String) {
    self.label = label; self.action = action; self.reason = reason
  }
  /// Applies deterministic policy without requesting a mail action.
  public static func evaluate(
    _ verdict: Verdict,
    strength: FilteringStrength = .balanced,
    review: ReviewTreatment = .orangeFlag
  ) throws -> Decision {
    _ = try verdict.validated()
    let label =
      verdict.label == .junk && verdict.confidence < strength.threshold
      ? MailLabel.review : verdict.label
    let action: MailAction
    switch label {
      case .inbox: action = .none
      case .review: action = review == .orangeFlag ? .orangeFlag : .orangeBackground
      case .junk: action = .moveToJunk
    }
    return .init(label: label, action: action, reason: verdict.reason)
  }
}
