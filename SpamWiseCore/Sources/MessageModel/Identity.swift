import Foundation
/**
 Account-scoped identity and content fingerprint for safe message resolution.

 An identity takes one of two forms:
 - **Apple Mail**: `accountID` is Mail's account identifier and `localID` Mail's scripting message
   ID. `mailboxValidity` is nil.
 - **IMAP**: `accountID` is the configured connection's identifier, `localID` the message UID,
   `mailboxValidity` the mailbox's UIDVALIDITY and `mailbox` its wire-encoded name. All three
   address the message and are revalidated before every operation.

 In both forms the storage ``key`` hashes only the account, Message-ID and content, so a message
 keeps its key, records and action claims when it moves between mailboxes.
 */
public struct MessageIdentity: Codable, Sendable, Hashable {
  /// The account the message belongs to; nil prevents account-scoped actions.
  public var accountID: String?
  /// RFC Message-ID claim, which is not globally unique or trusted.
  public var messageID: String?
  /// Mail's scripting message ID, or the IMAP UID.
  public var localID: Int?
  /// The IMAP mailbox's UIDVALIDITY, checked together with the UID; nil for Apple Mail.
  public var mailboxValidity: UInt64?
  /// The mailbox holding the message; IMAP addresses the UID within it, so it must match the server's name exactly.
  public var mailbox: String?
  /// SHA-256 fingerprint checked before mail actions.
  public var contentHash: String
  /// Stable storage, deduplication and action-claim key for this identity's form.
  public var key: String { mailboxValidity == nil ? mailKey : imapKey }
  /// Key of an Apple Mail identity. It omits the local ID, which Mail changes when a message moves.
  public var mailKey: String {
    Self.hash([accountID ?? "unresolved", messageID ?? "", contentHash])
  }
  /**
   Key of an IMAP identity, separated from Apple Mail keys by a namespace component.

   It omits the UID, UIDVALIDITY and mailbox: a message moved or restored in any client receives
   a new UID, and a UIDVALIDITY reset renumbers the whole mailbox.
   */
  public var imapKey: String {
    Self.hash(["imap", accountID ?? "unresolved", messageID ?? "", contentHash])
  }
  /// Creates an identity as given; a non-nil `mailboxValidity` makes it an IMAP identity keyed by ``imapKey``.
  public init(
    accountID: String?,
    messageID: String? = nil,
    localID: Int? = nil,
    mailboxValidity: UInt64? = nil,
    mailbox: String? = nil,
    contentHash: String
  ) {
    self.accountID = accountID; self.messageID = messageID; self.localID = localID
    self.mailboxValidity = mailboxValidity
    self.mailbox = mailbox; self.contentHash = contentHash
  }
  private static func hash(_ components: [String]) -> String {
    stableHash(Data(components.joined(separator: "\u{0}").utf8))
  }
}
