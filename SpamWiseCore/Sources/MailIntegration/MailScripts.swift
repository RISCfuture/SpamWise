import Foundation
public import SpamWiseCore

/// Escaped AppleScript programs for bounded, account-scoped Mail access.
public enum MailScripts {
  /// Escapes text for use as an AppleScript string literal.
  public static func literal(_ value: String) -> String {
    "\""
      + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(
        of: "\"",
        with: "\\\""
      ).replacingOccurrences(of: "\r", with: "\\r").replacingOccurrences(of: "\n", with: "\\n")
      .replacingOccurrences(of: "\t", with: "\\t") + "\""
  }
  /// Shared account and message resolution handlers.
  public static let helpers = """
    on collectMatches(boxes, wantedID, wantedLocal)
        set found to {}
        tell application "Mail"
            repeat with b in boxes
                if wantedID is not "" then
                    set hits to (every message of b whose message id is wantedID)
                else
                    set hits to (every message of b whose id is wantedLocal)
                end if
                set found to found & hits
                if (count of found) > 1 then return found
                set children to mailboxes of b
                if (count of children) > 0 then set found to found & my collectMatches(children, \
    wantedID, wantedLocal)
                if (count of found) > 1 then return found
            end repeat
        end tell
        return found
    end collectMatches
    on envelope(m)
        tell application "Mail"
            return {id of account of mailbox of m, name of mailbox of m, id of m, message id of m, \
    source of m}
        end tell
    end envelope
    """
  /// Resolves exactly one account-scoped message and rejects stale content.
  public static func lookup(
    _ identity: MessageIdentity,
    action: MailAction = .none,
    expectedSource: String? = nil
  ) throws -> String {
    guard let account = identity.accountID, !account.isEmpty,
      identity.messageID != nil || identity.localID != nil
    else { throw IntegrationError.ambiguous }
    var operation = "return my envelope(targetMessage)"
    if action != .none {
      guard let expectedSource else { throw IntegrationError.staleMessage }
      let change: String
      switch action {
        case .orangeFlag: change = "set flag index of targetMessage to 1"
        case .orangeBackground: change = "set background color of targetMessage to orange"
        case .moveToJunk, .moveToInbox:
          let role = action == .moveToJunk ? "junk mailbox" : "inbox"
          change = """
            set destinations to {}
            repeat with b in (mailboxes of \(role))
                if (id of account of b) is \(literal(account)) then set end of destinations to \
            contents of b
            end repeat
            if (count of destinations) is not 1 then error "Account mailbox unresolved" number -1701
            move targetMessage to item 1 of destinations
            """
        case .none: change = ""
      }
      operation =
        "if (source of targetMessage) is not \(literal(expectedSource)) then error \"Message changed\" number -1702\n"
        + change + "\nreturn true"
    }
    return helpers + "\n" + """
      with timeout of 8 seconds
          tell application "Mail"
              set candidates to (every account whose id is \(literal(account)))
              if (count of candidates) is not 1 then error "Account unresolved" number -1701
              set matches to my collectMatches(mailboxes of item 1 of candidates, \
      \(literal(identity.messageID ?? "")), \(identity.localID ?? -1))
              if (count of matches) is not 1 then error "Message ambiguous" number -1701
              set targetMessage to item 1 of matches
              \(operation)
          end tell
      end timeout
      """
  }
  /// Builds a bounded special-mailbox read script.
  public static func recent(limit: Int, mailbox: String = "inbox") -> String {
    let role = ["inbox", "sent mailbox", "junk mailbox"].contains(mailbox) ? mailbox : "inbox"
    return helpers + "\n" + """
      with timeout of 8 seconds
          tell application "Mail"
              set rows to {}
              set candidates to messages of \(role)
              set n to count of candidates
              if n > \(max(1, min(1000, limit))) then set n to \(max(1, min(1000, limit)))
              if n > 0 then
                  repeat with i from 1 to n
                      set end of rows to my envelope(item i of candidates)
                  end repeat
              end if
              return rows
          end tell
      end timeout
      """
  }
  /// Script requiring exactly one selected message.
  public static let selected =
    helpers + "\n" + """
      with timeout of 8 seconds
          tell application "Mail"
              set selectedMessages to selection
              if (count of selectedMessages) is not 1 then error "Select one disposable probe" \
      number -1701
              return my envelope(item 1 of selectedMessages)
          end tell
      end timeout
      """
  /// Reads Mail account identifiers and display names.
  public static let accounts = """
    with timeout of 8 seconds
        tell application "Mail"
            set resultRows to {}
            repeat with a in accounts
                set end of resultRows to {id of a, name of a}
            end repeat
            return resultRows
        end tell
    end timeout
    """
}
