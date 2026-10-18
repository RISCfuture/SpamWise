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
      let fields = try await invoke(.destinations(accountID: accountID)).list,
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
  static let destinationHandlers = """
    on boxNames(boxes)
        set names to {}
        repeat with b in boxes
            tell application "Mail" to set end of names to name of (contents of b)
        end repeat
        return names
    end boxNames
    on \(MailHandler.destinationNames.rawValue)(accountID)
        with timeout of \(eventTimeoutSeconds) seconds
            my accountByID(accountID)
            set inboxNames to my boxNames(my roleBoxes("\(MailboxRole.inbox.rawValue)", accountID))
            set junkNames to my boxNames(my roleBoxes("\(MailboxRole.junk.rawValue)", accountID))
            return {inboxNames, junkNames}
        end timeout
    end \(MailHandler.destinationNames.rawValue)
    """
}
