import Foundation
public import Classifier

/// Provisional confidence thresholds, pending held-out calibration.
public enum FilteringStrength: String, Codable, Sendable, CaseIterable {
  case conservative, balanced, aggressive
  /// Minimum provisional confidence required to act on a Junk verdict.
  public var threshold: Int {
    switch self { case .conservative: 99;  case .balanced: 95;  case .aggressive: 90
    }
  }
}
/// The annotation applied to Review messages left in Inbox.
public enum ReviewTreatment: String, Codable, Sendable, CaseIterable {
  case orangeFlag, orangeBackground
}
/// The supported action vocabulary deliberately contains no deletion or Trash operation.
public enum MailAction: String, Codable, Sendable {
  case none, orangeFlag, orangeBackground, moveToJunk, moveToInbox
}
/// Observed dispatch state, independent of the model verdict.
public enum ActionOutcome: String, Codable, Sendable {
  case noAction, dryRun, paused, pending, requested, applied, failed, unclassified, superseded,
    duplicate, integrationUnavailable
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
