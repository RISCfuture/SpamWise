import SpamWiseCore

/// Mail.app's current special-mailbox mapping, without inferring provider-side labels.
public struct MailDestinations: Sendable {
  /// Registrable domains of Gmail's incoming servers, which also serve Google Workspace accounts.
  private static let gmailDomains: Set<String> = ["gmail.com", "googlemail.com"]
  /// Top-level folders that hold Gmail's system mailboxes, Spam among them, over IMAP.
  private static let gmailSystemFolders: Set<String> = ["[Gmail]", "[Google Mail]"]

  /// Stable Mail account identifier.
  public let accountID: String
  /// Paths returned for this account's Inbox role; a valid mapping has one candidate.
  public let inbox: [String]
  /**
   Paths returned for this account's Junk role; a valid mapping has one candidate.

   Each path names the mailbox's parent folders first, separated by slashes, as in `[Gmail]/Spam`.
   */
  public let junk: [String]
  /// Host name of the account's incoming mail server, or empty when Mail reports none.
  public let server: String

  /// Whether both Mail.app roles resolve uniquely; this does not validate server behavior.
  public var isUnambiguous: Bool { inbox.count == 1 && junk.count == 1 }

  /// Whether the account's incoming mail server is Gmail's.
  public var isGmail: Bool {
    DomainResolver().registrableDomain(server).map(Self.gmailDomains.contains) ?? false
  }

  /**
   Whether this Gmail account's one Junk mailbox is a label rather than Gmail's system Spam.

   Junk moves still land in the account's own Junk mailbox, but Gmail's filter never sees them
   and other devices don't treat the mail as spam, so this warrants a warning, not a refusal.
   */
  public var junkBypassesGmailSpam: Bool {
    guard isGmail, junk.count == 1, let folder = junk[0].split(separator: "/").first else {
      return false
    }
    return !Self.gmailSystemFolders.contains(String(folder))
  }
}

extension AppleMailAdapter {
  /// Reads special-mailbox paths and the incoming server without changing messages.
  public func destinations(accountID: String) async throws -> MailDestinations {
    guard !accountID.isEmpty,
      let fields = try await interactively({
        try await invoke(.destinations(accountID: accountID))
      }).list,
      fields.count == 3, let inbox = fields[0].list, let junk = fields[1].list,
      let server = fields[2].string,
      inbox.allSatisfy({ $0.string != nil }), junk.allSatisfy({ $0.string != nil })
    else { throw IntegrationError.scriptFailed }
    return MailDestinations(
      accountID: accountID,
      inbox: inbox.compactMap(\.string),
      junk: junk.compactMap(\.string),
      server: server
    )
  }
}

extension MailScripts {
  static let destinationHandlers = """
    on boxPath(b)
        tell application "Mail"
            try
                set parentBox to container of b
                get account of parentBox
            on error number failureNumber
                if \(propagatedFailureList) contains failureNumber then error number failureNumber
                return name of b
            end try
            return my boxPath(parentBox) & "/" & (name of b)
        end tell
    end boxPath
    on boxPaths(boxes)
        set paths to {}
        repeat with b in boxes
            set end of paths to my boxPath(contents of b)
        end repeat
        return paths
    end boxPaths
    on serverName(targetAccount)
        tell application "Mail"
            try
                return server name of targetAccount
            on error number failureNumber
                if \(propagatedFailureList) contains failureNumber then error number failureNumber
                return ""
            end try
        end tell
    end serverName
    on \(MailHandler.destinationNames.rawValue)(accountID)
        with timeout of \(eventTimeoutSeconds) seconds
            set targetAccount to my accountByID(accountID)
            set inboxPaths to my boxPaths(my roleBoxes("\(MailboxRole.inbox.rawValue)", accountID))
            set junkPaths to my boxPaths(my roleBoxes("\(MailboxRole.junk.rawValue)", accountID))
            return {inboxPaths, junkPaths, my serverName(targetAccount)}
        end timeout
    end \(MailHandler.destinationNames.rawValue)
    """
}
