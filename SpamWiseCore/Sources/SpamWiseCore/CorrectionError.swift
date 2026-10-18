public import Foundation

/// Failures that prevent a correction from being saved.
public protocol CorrectionFailure: Error {}

/// Why a correction was rejected before any rule, label or mail action was saved.
public enum CorrectionError: CorrectionFailure, Sendable, Equatable, LocalizedError {
  /// The Activity record being corrected is no longer retained.
  case recordNotFound
  /// Review corrections apply only to one sender address.
  case reviewRequiresAddressScope
  /// The record has no single readable sender address to write a rule for.
  case unreadableSender
  /// The sender's address has no registrable domain for a domain-wide rule.
  case noRegistrableDomain(sender: String)
  /// A general description of the rejected correction.
  public var errorDescription: String? { String(localized: "The correction couldn’t be saved.") }
  /// The condition that rejected this correction.
  public var failureReason: String? {
    switch self {
      case .recordNotFound:
        String(localized: "The message’s Activity record is no longer available.")
      case .reviewRequiresAddressScope:
        String(localized: "Review corrections apply only to the sender’s address, not its domain.")
      case .unreadableSender:
        String(localized: "The message has no single readable sender address.")
      case .noRegistrableDomain(let sender):
        String(localized: "“\(sender)” has no registrable domain for a domain-wide rule.")
    }
  }
}

/// Failures while reading or acting on a retained Activity record.
public protocol DecisionRecordFailure: Error {}

/// A retained Activity record that is missing or not in the state an operation requires.
public enum DecisionRecordError: DecisionRecordFailure, Sendable, Equatable, LocalizedError {
  /// The record is no longer retained.
  case notFound
  /// The record is not an uncorrected dry-run preview.
  case notPreview
  /// The record is not an unclassified result that can be classified again.
  case notUnclassified
  /// The mail client no longer has the record's message.
  case messageUnavailable
  /// A general description of the failed record operation.
  public var errorDescription: String? {
    String(localized: "The Activity record couldn’t be used.")
  }
  /// The record state that prevented the operation.
  public var failureReason: String? {
    switch self {
      case .notFound: String(localized: "The Activity record is no longer available.")
      case .notPreview:
        String(localized: "Only an uncorrected dry-run preview can be applied.")
      case .notUnclassified: String(localized: "Only an unclassified message can be retried.")
      case .messageUnavailable:
        String(localized: "The message is no longer available in the mail client.")
    }
  }
}
