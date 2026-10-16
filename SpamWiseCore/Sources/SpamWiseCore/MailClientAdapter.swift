public import Foundation
/// Raw message bytes paired with account-scoped identity.
public struct MailEnvelope: Sendable {
  /// Account and content identity used to resolve this message safely.
  public var identity: MessageIdentity
  /// Original message data used for parsing and identity checks.
  public var raw: Data
  /// Creates a MailEnvelope with the supplied configuration.
  public init(identity: MessageIdentity, raw: Data) { self.identity = identity; self.raw = raw }
}
/// Whether the adapter observed the requested action's result in its mail client.
public struct ActionReceipt: Sendable {
  /// Client observation of completion, without a separate mail-server acknowledgement.
  public var confirmed: Bool
  /// Fresh account-scoped identity observed after a mailbox move, when the adapter can prove it.
  public var updatedIdentity: MessageIdentity?
  /// Creates an ActionReceipt with the supplied configuration.
  public init(confirmed: Bool, updatedIdentity: MessageIdentity? = nil) {
    self.confirmed = confirmed; self.updatedIdentity = updatedIdentity
  }
}
/// Message discovery, history, and non-destructive Mail action operations.
public protocol MailClientAdapter: Sendable {
  /// Resolves one message using its account-scoped identity.
  func lookup(_ identity: MessageIdentity) async throws -> MailEnvelope?
  /// Discovers a bounded page of incoming messages.
  func recentMessages(limit: Int) async throws -> [MailEnvelope]
  /// Imports available account-scoped relationship history.
  func importHistory() async throws -> [String: HistoryIndex]
  /// Performs a supported action and reports the observed client state.
  func perform(_ action: MailAction, for identity: MessageIdentity) async throws -> ActionReceipt
}
/// Failures while resolving messages or executing mail-client operations.
public protocol MailIntegrationFailure: Error {}

/// Permission, resolution, or execution errors from a mail adapter.
public enum IntegrationError: String, MailIntegrationFailure, LocalizedError, Sendable {
  /// The user or system denied access to the mail client.
  case permissionDenied
  /// The requested message or mail service is unavailable.
  case unavailable
  /// More than one message matches the requested identity.
  case ambiguous
  /// The resolved message no longer matches its recorded state.
  case staleMessage
  /// The account has not passed explicit action validation.
  case accountUnverified
  /// The mail client could not execute the requested operation.
  case scriptFailed
  /// A non-sensitive description suitable for presentation.
  public var errorDescription: String? { String(localized: "The Mail action is unavailable.") }
  /// The non-sensitive cause of the unavailable operation.
  public var failureReason: String? {
    switch self {
      case .permissionDenied: String(localized: "Permission to control Mail was denied.")
      case .unavailable: String(localized: "The requested message or Mail service is unavailable.")
      case .ambiguous: String(localized: "More than one message matches the requested identity.")
      case .staleMessage: String(localized: "The message no longer matches its recorded state.")
      case .accountUnverified: String(localized: "The account has not passed action validation.")
      case .scriptFailed: String(localized: "Mail could not complete the requested operation.")
    }
  }
}
