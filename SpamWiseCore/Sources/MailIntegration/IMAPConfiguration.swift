import Foundation
import SpamWiseCore

/// Explicit account connection settings. Secrets are supplied separately for each connection.
public struct IMAPConfiguration: Codable, Sendable, Equatable {
  /// The implicit-TLS IMAP port used when none is given.
  public static let defaultPort: UInt16 = 993
  private static let maximumIdentifierBytes = 256
  private static let maximumHostBytes = 253
  /// Stable application account identifier, distinct from Apple Mail account identifiers.
  public var id: String
  /// TLS certificate hostname of the IMAP server.
  public var host: String
  /// Implicit TLS port; defaults to ``defaultPort``.
  public var port: UInt16
  /// Authentication identity, never inferred from Mail databases.
  public var username: String
  /// Explicit opt-in to actions after this adapter validates the account read-only.
  public var allowsActions: Bool
  /// Creates connection settings without embedding a credential.
  public init(
    id: String,
    host: String,
    port: UInt16 = defaultPort,
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
    port = try values.decodeIfPresent(UInt16.self, forKey: .port) ?? Self.defaultPort
    username = try values.decode(String.self, forKey: .username)
    allowsActions = try values.decodeIfPresent(Bool.self, forKey: .allowsActions) ?? false
    try validate()
  }
  /**
   Checks that the identifier, host, port and username form a usable endpoint.

   Decoding runs this check, so a decoded configuration is always valid; call it before
   saving a configuration built in memory.
   - Throws: ``IMAPError/invalidConfiguration`` for an empty or oversized identifier, a host
     that is empty, too long or not an ASCII hostname, port zero, or a username that is empty
     or can't be sent as IMAP text.
   */
  public func validate() throws {
    guard !id.isEmpty, id.utf8.count <= Self.maximumIdentifierBytes, !host.isEmpty,
      host.utf8.count <= Self.maximumHostBytes, port > 0,
      host.utf8.allSatisfy({
        [45, 46].contains($0) || (48...57).contains($0) || (65...90).contains($0)
          || (97...122).contains($0)
      }),
      !username.isEmpty
    else { throw IMAPError.invalidConfiguration }
    try IMAPWireText.validate(username)
  }
  private enum CodingKeys: String, CodingKey { case id, host, port, username, allowsActions }
}

extension IMAPConfiguration {
  /// Hash of the account, case-insensitive host, port and username; keys validation evidence and sweep progress.
  var endpointFingerprint: String { fingerprint(host: host.lowercased()) }
  /// Hash of the account, host as written, port and username; sweep progress saved under it
  /// is read when none is saved under ``endpointFingerprint``.
  var legacyEndpointFingerprint: String { fingerprint(host: host) }

  private func fingerprint(host: String) -> String {
    stableHash(Data([id, host, String(port), username].joined(separator: "\u{0}").utf8))
  }
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

  /// Server can move mail atomically into a unique Junk mailbox.
  public var movesToJunk: Bool { supportsMove && junkMailbox != nil }
}
