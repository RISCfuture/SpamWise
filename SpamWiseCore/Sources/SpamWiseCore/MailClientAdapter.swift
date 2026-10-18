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
  /// Whether this integration can perform `action` at all; Pipeline records unsupported actions without claiming them.
  func supports(_ action: MailAction) async -> Bool
  /// Performs a supported action on the message only where it was recorded.
  func perform(_ action: MailAction, for identity: MessageIdentity) async throws -> ActionReceipt
  /// Performs a user-requested correction, which may find the message outside its recorded mailbox.
  func performCorrection(_ action: MailAction, for identity: MessageIdentity) async throws
    -> ActionReceipt
  /// Marks an exact message read only while it remains in this account's Junk mailbox.
  func markReadInJunk(_ identity: MessageIdentity) async throws -> ActionReceipt
}
extension MailClientAdapter {
  /// Integrations support every action unless they say otherwise.
  public func supports(_ action: MailAction) async -> Bool { true }
  /// Integrations without broader resolution apply corrections where the message was recorded.
  public func performCorrection(_ action: MailAction, for identity: MessageIdentity) async throws
    -> ActionReceipt
  {
    try await perform(action, for: identity)
  }
  /// Unsupported integrations leave read status unchanged.
  public func markReadInJunk(_ identity: MessageIdentity) async throws -> ActionReceipt {
    throw IntegrationError.unavailable
  }
}
/// Failures while resolving messages or executing mail-client operations.
public protocol MailIntegrationFailure: Error {}

/// A failure an adapter raised before it sent any mail command, so the message is unchanged.
public struct ActionNotAttempted: MailIntegrationFailure, LocalizedError {
  /// The failure that stopped the action.
  public let cause: any Error
  /// A non-sensitive description suitable for presentation.
  public var errorDescription: String? {
    String(
      localized: "The Mail action was not attempted; the message is unchanged.",
      bundle: .module
    )
  }
  /// The non-sensitive cause, when the underlying failure provides one.
  public var failureReason: String? { (cause as? any LocalizedError)?.failureReason }
  /// Wraps the failure that stopped an action before dispatch.
  public init(cause: any Error) { self.cause = cause }
}

/// Permission, resolution, or execution errors from a mail adapter.
public enum IntegrationError: MailIntegrationFailure, LocalizedError, Sendable, Equatable {
  /// The user or system denied access to the mail client.
  case permissionDenied
  /// The requested message or mail service is unavailable.
  case unavailable
  /// More than one message with identical content matches the requested identity.
  case ambiguous
  /// The configured account or exact mailbox path cannot be resolved uniquely.
  case folderUnresolved
  /// The resolved message no longer matches its recorded state.
  case staleMessage
  /// The account's Inbox and Junk mailboxes have not been validated.
  case accountUnverified
  /// The mail client could not execute the requested operation.
  case scriptFailed
  /// The mail client has no unique account with the recorded identifier.
  case accountUnresolved
  /// The account's Inbox or Junk mailbox cannot be identified uniquely.
  case mailboxUnresolved
  /// No message matches the recorded identity.
  case messageNotFound
  /// The message left the mailbox where it was recorded, so it was not changed.
  case messageMoved
  /// The message has no Message-ID, so a move could not be confirmed and was not attempted.
  case missingMessageID
  /// The message source exceeds the readable size limit.
  case messageTooLarge
  /// The mail client's selection holds a number of messages outside the accepted range.
  case selectionCount(minimum: Int, maximum: Int)
  /// The user already set a different flag or color, which is retained.
  case existingAnnotation
  /// The mail client holds more mailboxes, or deeper nesting, than SpamWise lists.
  case folderLimit(count: Int, depth: Int)
  /// The mail client did not respond within the time limit; any requested change is unknown.
  case timedOut
  /// The expected result was not observed before the observation window ended.
  case actionUnconfirmed
  /// The selected message is not an Inbox message named as a disposable SpamWise probe.
  case notProbeMessage
  /// A non-sensitive description suitable for presentation.
  public var errorDescription: String? {
    String(localized: "The Mail action is unavailable.", bundle: .module)
  }
  /// The non-sensitive cause of the unavailable operation.
  public var failureReason: String? {
    switch self {
      case .permissionDenied:
        String(localized: "Permission to control Mail was denied.", bundle: .module)
      case .unavailable:
        String(localized: "The requested message or Mail service is unavailable.", bundle: .module)
      case .ambiguous:
        String(localized: "More than one message matches the requested identity.", bundle: .module)
      case .folderUnresolved:
        String(
          localized:
            "The configured account or folder could not be found uniquely. Select the folder again.",
          bundle: .module
        )
      case .staleMessage:
        String(localized: "The message no longer matches its recorded state.", bundle: .module)
      case .accountUnverified:
        String(
          localized: "The account’s Inbox and Junk mailboxes haven’t been validated.",
          bundle: .module
        )
      case .scriptFailed:
        String(localized: "Mail could not complete the requested operation.", bundle: .module)
      default: resolutionReason ?? limitReason
    }
  }
  private var resolutionReason: String? {
    switch self {
      case .accountUnresolved:
        String(
          localized: "Mail has no unique account with the recorded identifier.",
          bundle: .module
        )
      case .mailboxUnresolved:
        String(
          localized: "Mail couldn’t identify this account’s mailbox uniquely.",
          bundle: .module
        )
      case .messageNotFound:
        String(localized: "The message couldn’t be found in Mail.", bundle: .module)
      case .messageMoved:
        String(
          localized:
            "The message is no longer in the mailbox where SpamWise found it, so it was left in place.",
          bundle: .module
        )
      case .missingMessageID:
        String(
          localized:
            "The message has no Message-ID, so SpamWise can’t confirm a move and left it in place.",
          bundle: .module
        )
      case .existingAnnotation:
        String(
          localized:
            "The message already has a flag or color you set, so SpamWise left it unchanged.",
          bundle: .module
        )
      case .notProbeMessage:
        String(
          localized:
            "Select one message in the account’s Inbox whose subject starts with “[SpamWise Probe]”.",
          bundle: .module
        )
      default: nil
    }
  }
  private var limitReason: String? {
    switch self {
      case .messageTooLarge:
        String(
          localized: "The message is too large for SpamWise to read, so it was left unchanged.",
          bundle: .module
        )
      case .selectionCount(let minimum, let maximum) where minimum == 1 && maximum == 1:
        String(localized: "Select exactly one message in Mail.", bundle: .module)
      case .selectionCount(let minimum, let maximum):
        String(
          localized:
            "Select \(minimum, format: .number) to \(maximum, format: .number) messages in Mail.",
          bundle: .module
        )
      case .folderLimit(let count, let depth):
        String(
          localized:
            "Mail has more than \(count, format: .number) mailboxes or folders nested more than \(depth, format: .number) levels deep.",
          bundle: .module
        )
      case .timedOut:
        String(
          localized:
            "Mail didn’t respond in time. Any requested change may still happen; check the message in Mail.",
          bundle: .module
        )
      case .actionUnconfirmed:
        String(
          localized:
            "Mail didn’t show the expected result before the observation window ended.",
          bundle: .module
        )
      default: nil
    }
  }
}
