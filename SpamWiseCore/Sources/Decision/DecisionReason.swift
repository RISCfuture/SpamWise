public import Classifier
public import Signals
import Foundation

/// Why a decision was reached, stored as data and rendered in the user's language for display.
public enum DecisionReason: Codable, Sendable, Equatable {
  /// A sender rule, content rule or trusted relationship decided the message.
  case gate(GateReason)
  /// The message matched a campaign the user explicitly marked as junk, so it was flagged for Review.
  case campaign
  /// The classifier's own explanation, written in the language its instructions request.
  case model(String)
  /// The user corrected the decision at the given rule scope.
  case userCorrection(scope: RuleScope)
  /// The user selected the message in Mail for correction without classifying it.
  case selectedForCorrection
  /// A synthetic message verified the provider connection.
  case connectionVerified
  /// Filtering was paused, so the message was not classified.
  case paused
  /// The message could not be parsed.
  case messageUnreadable
  /// The message has no single readable sender, so it was flagged for Review without classification.
  case unreadableSender
  /// The classifier failed for the given reason.
  case classificationFailed(ClassificationError)
  /// The monthly spending limit refused the request before anything was sent to the provider.
  case spendingLimitReached
  /// Shared storage could not be read or written.
  case storageUnavailable
  /// Another operation failed while processing the message.
  case processingFailed
  /// Another callback was already processing the same message.
  case duplicateCallback
  /// An earlier decision already claimed the message's action.
  case actionAlreadyClaimed
  /// Untyped text from a record that an earlier version stored, shown as written.
  case legacy(String)
  /// A stored reason this version does not recognize, such as one a newer version wrote.
  case unrecognized

  /**
   Maps reason text that an earlier version stored to the matching reason, or keeps it as
   ``legacy(_:)``.

   - Parameters:
     - text: The stored reason text.
     - label: The stored decision label, which supplies a legacy content rule's disposition.
   */
  public init(legacy text: String, label: MailLabel?) {
    if let id = Self.suffix(of: text, after: Self.legacyContentRulePrefix).flatMap(UUID.init) {
      self = .gate(.contentRule(id: id, disposition: label == .inbox ? .allow : .block, note: nil))
    } else if let error = Self.suffix(of: text, after: Self.legacyFailurePrefix)
      .flatMap(ClassificationError.init)
    {
      self = .classificationFailed(error)
    } else {
      self = Self.fixedReasons.first { $0.diagnosticDescription == text } ?? .legacy(text)
    }
  }
}

extension DecisionReason {
  private static let legacyContentRulePrefix = "gate: user content rule "
  private static let legacyFailurePrefix = "unclassified: "
  private static let fixedReasons: [Self] =
    RuleScope.allCases.flatMap { scope in
      [RuleDisposition.allow, .block].map { .gate(.senderRule(scope: scope, disposition: $0)) }
        + [.userCorrection(scope: scope)]
    } + [
      .gate(.contact), .gate(.priorCorrespondence), .gate(.orderHistory), .campaign,
      .selectedForCorrection, .connectionVerified, .paused, .messageUnreadable,
      .spendingLimitReached, .storageUnavailable, .processingFailed, .duplicateCallback,
      .actionAlreadyClaimed
    ]

  /// The explanation in the user's language.
  public var localizedDescription: String {
    switch self {
      case .gate(let gate): gate.localizedDescription
      case .campaign: String(localized: "Review: matches a campaign you marked as junk")
      case .model(let text), .legacy(let text): text
      case .userCorrection(.address): String(localized: "Your correction for this sender’s address")
      case .userCorrection(.domain): String(localized: "Your correction for this sender’s domain")
      case .selectedForCorrection: String(localized: "Selected in Mail for correction")
      case .connectionVerified: String(localized: "Haiku 5.5 connection verified")
      case .paused: String(localized: "Filtering paused")
      case .messageUnreadable: String(localized: "Not classified: the message couldn’t be read.")
      case .unreadableSender: String(localized: "Review: the sender’s address couldn’t be read")
      case .classificationFailed(let error):
        String(localized: "Not classified: \(error.failureReason ?? error.localizedDescription)")
      case .spendingLimitReached:
        String(
          localized:
            "Not classified: the monthly spending limit was reached, so nothing was sent to the provider."
        )
      case .storageUnavailable: String(localized: "Not classified: shared storage was unavailable.")
      case .processingFailed:
        String(localized: "Not classified: processing failed. Mail was left unchanged.")
      case .duplicateCallback: String(localized: "Already being processed")
      case .actionAlreadyClaimed: String(localized: "Already handled; the earlier decision is kept")
      case .unrecognized: String(localized: "Reason recorded by a different version of SpamWise")
    }
  }

  /// Stable English form for logs, evaluation reports and model correction examples.
  public var diagnosticDescription: String {
    switch self {
      case .gate(let gate): gate.diagnosticDescription
      case .campaign: "review: authenticated match to explicitly junked campaign"
      case .model(let text), .legacy(let text): text
      case .userCorrection(let scope): "User correction (\(scope.rawValue))"
      case .selectedForCorrection: "Explicitly selected for correction"
      case .connectionVerified: "Haiku 5.5 connection verified"
      case .paused: "Filtering paused"
      case .messageUnreadable: Self.legacyFailurePrefix + "message parsing failed"
      case .unreadableSender: "review: no single readable From mailbox"
      case .classificationFailed(let error): Self.legacyFailurePrefix + error.rawValue
      case .spendingLimitReached:
        Self.legacyFailurePrefix + "spending limit reached; no provider request was made"
      case .storageUnavailable: Self.legacyFailurePrefix + "shared storage unavailable"
      case .processingFailed: Self.legacyFailurePrefix + "persistence or integration unavailable"
      case .duplicateCallback: "Duplicate callback already in progress"
      case .actionAlreadyClaimed: "Action already claimed; the earlier decision is retained"
      case .unrecognized: "Unrecognized reason"
    }
  }

  /// The diagnostic form without model or legacy text, safe for content-free support exports.
  public var diagnosticCategory: String {
    switch self {
      case .model: "model"
      case .legacy: "legacy"
      default: diagnosticDescription
    }
  }

  private static func suffix(of text: String, after prefix: String) -> String? {
    text.hasPrefix(prefix) ? String(text.dropFirst(prefix.count)) : nil
  }
}

extension GateReason {
  /// The explanation in the user's language.
  public var localizedDescription: String {
    switch self {
      case .senderRule(.address, .allow):
        String(localized: "Allowed by your rule for this sender’s address")
      case .senderRule(.address, .block):
        String(localized: "Blocked by your rule for this sender’s address")
      case .senderRule(.domain, .allow):
        String(localized: "Allowed by your rule for this sender’s domain")
      case .senderRule(.domain, .block):
        String(localized: "Blocked by your rule for this sender’s domain")
      case .contentRule(_, .allow, let note?):
        String(localized: "Allowed by your content rule “\(note)”")
      case .contentRule(_, .block, let note?):
        String(localized: "Blocked by your content rule “\(note)”")
      case .contentRule(_, .allow, nil): String(localized: "Allowed by one of your content rules")
      case .contentRule(_, .block, nil): String(localized: "Blocked by one of your content rules")
      case .contact: String(localized: "Allowed: the sender is in your Contacts")
      case .priorCorrespondence: String(localized: "Allowed: you have replied to this sender")
      case .orderHistory:
        String(localized: "Allowed: this sender has sent authenticated order mail before")
    }
  }
}
