/// Explicit account connection settings. Secrets are supplied separately for each connection.
public struct IMAPConfiguration: Codable, Sendable, Equatable {
  private static let maximumIdentifierBytes = 256
  private static let maximumHostBytes = 253
  /// Stable application account identifier, distinct from Apple Mail account identifiers.
  public var id: String
  /// TLS certificate hostname of the IMAP server.
  public var host: String
  /// Implicit TLS port; defaults to 993.
  public var port: UInt16
  /// Authentication identity, never inferred from Mail databases.
  public var username: String
  /// Explicit opt-in to actions after this adapter validates the account read-only.
  public var allowsActions: Bool
  /// Creates connection settings without embedding a credential.
  public init(
    id: String,
    host: String,
    port: UInt16 = 993,
    username: String,
    allowsActions: Bool = false
  ) {
    self.id = id; self.host = host; self.port = port; self.username = username
    self.allowsActions = allowsActions
  }
  /// Decodes an explicit endpoint with TLS and action-disabled defaults.
  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(String.self, forKey: .id)
    host = try values.decode(String.self, forKey: .host)
    port = try values.decodeIfPresent(UInt16.self, forKey: .port) ?? 993
    username = try values.decode(String.self, forKey: .username)
    allowsActions = try values.decodeIfPresent(Bool.self, forKey: .allowsActions) ?? false
    try validate()
  }
  func validate() throws {
    guard !id.isEmpty, id.utf8.count <= Self.maximumIdentifierBytes, !host.isEmpty,
      host.utf8.count <= Self.maximumHostBytes, port > 0,
      host.utf8.allSatisfy({
        [45, 46].contains($0) || (48...57).contains($0) || (65...90).contains($0)
          || (97...122).contains($0)
      }),
      !username.isEmpty
    else { throw IMAPError.invalidConfiguration }
    _ = try IMAPSession.quote(username)
  }
  private enum CodingKeys: String, CodingKey { case id, host, port, username, allowsActions }
}

/// Ephemeral authentication material, obtained from Keychain or an explicit caller-owned source.
public enum IMAPCredential: Sendable {
  case password(String)
  case oauthBearer(String)
}

/// Observed capabilities and mailbox roles from a read-only connection check.
public struct IMAPValidation: Sendable, Equatable {
  /// Server supports the atomic UID MOVE operation.
  public var supportsMove: Bool
  /// Unique server-designated Junk mailbox, if available; names retain their wire encoding.
  public var junkMailbox: String?
  /// Unique server-designated Sent mailbox, if available; names retain their wire encoding.
  public var sentMailbox: String?
  /// Inbox UID namespace observed during validation.
  public var inboxValidity: UInt64
}
