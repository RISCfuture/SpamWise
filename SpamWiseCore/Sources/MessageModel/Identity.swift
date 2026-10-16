import Foundation
/// Account-scoped identity and content fingerprint for safe message resolution.
public struct MessageIdentity: Codable, Sendable, Hashable {
  /// Mail's account identifier; nil prevents account-scoped actions.
  public var accountID: String?
  /// RFC Message-ID claim, which is not globally unique or trusted.
  public var messageID: String?
  /// Mail's local scripting message identifier, when available.
  public var localID: Int?
  /// IMAP mailbox generation checked together with the UID before every operation.
  public var mailboxValidity: UInt64?
  /// The source mailbox name for display and diagnostics.
  public var mailbox: String?
  /// SHA-256 fingerprint checked before mail actions.
  public var contentHash: String
  /// Creates a MessageIdentity with the supplied configuration.
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
  /// Stable storage or deduplication key.
  public var key: String {
    if let mailboxValidity {
      return stableHash(
        Data(
          [
            accountID ?? "unresolved", mailbox ?? "", String(mailboxValidity),
            localID.map(String.init) ?? "", contentHash
          ].joined(separator: "\u{0}").utf8
        )
      )
    }
    return stableHash(
      Data(
        [accountID ?? "unresolved", messageID ?? "", contentHash].joined(separator: "\u{0}").utf8
      )
    )
  }
}
