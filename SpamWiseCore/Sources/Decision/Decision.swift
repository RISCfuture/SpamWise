import Foundation
public import Classifier

/// Provisional confidence thresholds, pending held-out calibration.
public enum FilteringStrength: String, Codable, Sendable, CaseIterable {
  /// Requires confidence of at least 99 before a Junk action, or category confidence of 95 for
  /// graymail the user chose Junk for.
  case conservative
  /// Requires confidence of at least 95 before a Junk action, or category confidence of 85 for
  /// graymail the user chose Junk for.
  case balanced
  /// Requires confidence of at least 90 before a Junk action, or category confidence of 75 for
  /// graymail the user chose Junk for.
  case aggressive
  /// Minimum provisional confidence required to act on a Junk verdict.
  public var threshold: Int {
    switch self { case .conservative: 99;  case .balanced: 95;  case .aggressive: 90
    }
  }
  /**
   Minimum category confidence for moving graymail to Junk because the user chose Junk for its
   category, whatever the verdict's label.

   Provisional pending the graymail adherence evaluation.
   */
  public var graymailThreshold: Int {
    switch self { case .conservative: 95;  case .balanced: 85;  case .aggressive: 75
    }
  }
}
/// The annotation applied to Review messages left in Inbox.
public enum ReviewTreatment: String, Codable, Sendable, CaseIterable {
  /// Marks Review messages with an orange flag.
  case orangeFlag = "orangeFlag"
  /// Marks Review messages with an orange background.
  case orangeBackground = "orangeBackground"
  /// The mail action that applies this annotation.
  public var action: MailAction { self == .orangeFlag ? .orangeFlag : .orangeBackground }
}
/// The supported action vocabulary deliberately contains no deletion or Trash operation.
public enum MailAction: String, Codable, Sendable {
  /// Leaves the message unchanged.
  case none
  /// Applies the orange Review flag.
  case orangeFlag = "orangeFlag"
  /// Applies the orange Review background.
  case orangeBackground = "orangeBackground"
  /// Moves the message into the account’s Junk mailbox.
  case moveToJunk = "moveToJunk"
  /// Moves the message into the account’s Inbox.
  case moveToInbox = "moveToInbox"
  /// Removes the orange Review flag, leaving any other flag the user set.
  case clearOrangeFlag = "clearOrangeFlag"
  /// Removes the orange Review background, leaving any other color the user set.
  case clearOrangeBackground = "clearOrangeBackground"

  /// The action that removes this Review annotation, or nil when this is not an annotation.
  public var clearingAnnotation: Self? {
    switch self {
      case .orangeFlag: .clearOrangeFlag
      case .orangeBackground: .clearOrangeBackground
      case .none, .moveToJunk, .moveToInbox, .clearOrangeFlag, .clearOrangeBackground: nil
    }
  }
}
/// Observed dispatch state, independent of the model verdict.
public enum ActionOutcome: String, Codable, Sendable {
  /// The decision requires no mail operation.
  case noAction = "noAction"
  /// Dry run suppressed the intended operation.
  case dryRun = "dryRun"
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
  case integrationUnavailable = "integrationUnavailable"
}
/// An intended label and supported mail action.
public struct Decision: Codable, Sendable, Equatable {
  /// Inbox, Review, or Junk; absent when unclassified.
  public var label: MailLabel?
  /// The intended supported Mail operation.
  public var action: MailAction
  /// The evidence or policy behind this result.
  public var reason: DecisionReason
  /// The user's preference for the verdict's graymail category, when one shaped this result.
  public var preference: GraymailPreference?
  /// Whether the user's Junk preference for the verdict's category, not its label, chose Junk.
  public var followsCategoryPreference: Bool {
    if case .categoryPreference = reason { true } else { false }
  }
  /// Records a label and action as given; ``evaluate(_:reason:strength:review:concealsContent:preference:)`` derives them by policy.
  public init(
    label: MailLabel?,
    action: MailAction,
    reason: DecisionReason,
    preference: GraymailPreference? = nil
  ) {
    self.label = label; self.action = action; self.reason = reason; self.preference = preference
  }
  /// Decodes a stored decision, mapping a reason this version cannot decode to ``DecisionReason/unrecognized``.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    label = try container.decodeIfPresent(MailLabel.self, forKey: .label)
    action = try container.decode(MailAction.self, forKey: .action)
    reason = (try? container.decode(DecisionReason.self, forKey: .reason)) ?? .unrecognized
    preference = try? container.decodeIfPresent(GraymailPreference.self, forKey: .preference)
  }
  /**
   Applies deterministic policy without requesting a mail action.

   - Parameters:
     - verdict: The validated classification.
     - reason: Why the verdict was reached; defaults to the verdict's own explanation.
     - strength: The Junk confidence and graymail category-confidence thresholds.
     - review: The annotation for Review messages.
     - concealsContent: Whether part of the message couldn't be read reliably; an Inbox verdict
       then becomes Review for ``DecisionReason/concealedContent``.
     - preference: The user's preference for the verdict's graymail category, or nil when none
       applies, as for gate decisions and mail that is not graymail.
   */
  public static func evaluate(
    _ verdict: Verdict,
    reason: DecisionReason? = nil,
    strength: FilteringStrength = .balanced,
    review: ReviewTreatment = .orangeFlag,
    concealsContent: Bool = false,
    preference: GraymailPreference? = nil
  ) throws -> Self {
    try evaluate(
      verdict,
      reason: reason,
      junkThreshold: strength.threshold,
      graymailThreshold: strength.graymailThreshold,
      review: review,
      concealsContent: concealsContent,
      preference: preference
    )
  }
  /**
   Applies deterministic policy at explicit thresholds, as calibration reports do when they score
   thresholds between the named strengths.

   - Parameters:
     - verdict: The validated classification.
     - reason: Why the verdict was reached; defaults to the verdict's own explanation.
     - junkThreshold: The minimum confidence for a Junk action; lower Junk verdicts become Review.
     - graymailThreshold: The minimum category confidence for moving graymail the user chose Junk
       for to Junk, whatever the verdict's label, for ``DecisionReason/categoryPreference(_:)``.
     - review: The annotation for Review messages.
     - concealsContent: Whether part of the message couldn't be read reliably; an Inbox verdict
       then becomes Review for ``DecisionReason/concealedContent``.
     - preference: The user's preference for the verdict's graymail category. Keep never moves a
       message to Junk, Review always flags it, and Junk never leaves it unflagged in Inbox.
   */
  public static func evaluate(
    _ verdict: Verdict,
    reason: DecisionReason? = nil,
    junkThreshold: Int,
    graymailThreshold: Int,
    review: ReviewTreatment = .orangeFlag,
    concealsContent: Bool = false,
    preference: GraymailPreference? = nil
  ) throws -> Self {
    _ = try verdict.validated()
    var label = verdict.label.bounded(by: preference)
    var reason = reason ?? .model(verdict.reason)
    if verdict.isPreferredJunk(preference, threshold: graymailThreshold) {
      (label, reason) = (.junk, .categoryPreference(verdict.category))
    } else if label == .junk, verdict.confidence < junkThreshold {
      label = .review
    }
    if concealsContent, label == .inbox { (label, reason) = (.review, .concealedContent) }
    let action: MailAction
    switch label {
      case .inbox: action = .none
      case .review: action = review.action
      case .junk: action = .moveToJunk
    }
    return .init(label: label, action: action, reason: reason, preference: preference)
  }
  private enum CodingKeys: String, CodingKey { case label, action, reason, preference }
}

extension Verdict {
  /// Whether the user chose Junk for this verdict's graymail category and the verdict is at least
  /// `threshold` sure of that category.
  fileprivate func isPreferredJunk(_ preference: GraymailPreference?, threshold: Int) -> Bool {
    guard preference == .junk, category.isGraymail, let categoryConfidence else { return false }
    return categoryConfidence >= threshold
  }
}

extension MailLabel {
  /// This label within the range a graymail preference allows.
  fileprivate func bounded(by preference: GraymailPreference?) -> Self {
    switch (preference, self) {
      case (.keep, .junk), (.review, _), (.junk, .inbox): .review
      default: self
    }
  }
}
