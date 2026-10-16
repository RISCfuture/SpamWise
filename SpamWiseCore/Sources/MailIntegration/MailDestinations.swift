import SpamWiseCore

/// Mail.app's current special-mailbox mapping, without inferring provider-side labels.
public struct MailDestinations: Sendable {
  /// Stable Mail account identifier.
  public let accountID: String
  /// Names returned for this account's Inbox role; a valid mapping has one candidate.
  public let inbox: [String]
  /// Names returned for this account's Junk role; a valid mapping has one candidate.
  public let junk: [String]
  /// Whether both Mail.app roles resolve uniquely; this does not validate server behavior.
  public var isUnambiguous: Bool { inbox.count == 1 && junk.count == 1 }
}

extension AppleMailAdapter {
  /// Reads special-mailbox names without changing messages or enabling actions.
  public func destinations(accountID: String) async throws -> MailDestinations {
    guard !accountID.isEmpty,
      let fields = try await runFolderScript(MailScripts.destinations(accountID: accountID)).list,
      fields.count == 2, let inbox = fields[0].list, let junk = fields[1].list,
      inbox.allSatisfy({ $0.string != nil }), junk.allSatisfy({ $0.string != nil })
    else { throw IntegrationError.scriptFailed }
    return MailDestinations(
      accountID: accountID,
      inbox: inbox.compactMap(\.string),
      junk: junk.compactMap(\.string)
    )
  }
}

extension MailScripts {
  /// Uses the same special-mailbox collections as action resolution, without reading content.
  public static func destinations(accountID: String) -> String {
    """
    with timeout of 8 seconds
        tell application "Mail"
            set candidates to (every account whose id is \(literal(accountID)))
            if (count of candidates) is not 1 then error "Account unresolved" number -1701
            set inboxNames to {}
            repeat with b in mailboxes of inbox
                if (id of account of b) is \(literal(accountID)) then set end of inboxNames to \
    name of b
            end repeat
            set junkNames to {}
            repeat with b in mailboxes of junk mailbox
                if (id of account of b) is \(literal(accountID)) then set end of junkNames to name \
    of b
            end repeat
            return {inboxNames, junkNames}
        end tell
    end timeout
    """
  }
}
