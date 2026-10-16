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
/// Whether the adapter acknowledged completion of a requested action.
public struct ActionReceipt: Sendable {
  /// Whether the adapter acknowledged completing the action.
  public var confirmed: Bool
  /// Creates an ActionReceipt with the supplied configuration.
  public init(confirmed: Bool) { self.confirmed = confirmed }
}
/// Message discovery, history, and non-destructive Mail action operations.
public protocol MailClientAdapter: Sendable {
  func lookup(_ identity: MessageIdentity) async throws -> MailEnvelope?
  func recentMessages(limit: Int) async throws -> [MailEnvelope]
  func importHistory() async throws -> [String: HistoryIndex]
  func perform(_ action: MailAction, for identity: MessageIdentity) async throws -> ActionReceipt
}
/// Permission, resolution, or execution errors from a mail adapter.
public enum IntegrationError: String, Error, LocalizedError, Sendable {
  case permissionDenied, unavailable, ambiguous, staleMessage, accountUnverified, scriptFailed
  /// A non-sensitive description suitable for presentation.
  public var errorDescription: String? { "Mail action unavailable: \(rawValue)." }
}
