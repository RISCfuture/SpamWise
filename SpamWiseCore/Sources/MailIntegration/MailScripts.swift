import Foundation
public import SpamWiseCore

/// Escaped AppleScript programs for bounded, account-scoped Mail access.
public enum MailScripts {
  private static let maximumPageSize = 1000
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
  /// Captures a bounded selection without changing read status or mailbox membership.
  public static let selectedBatch =
    helpers + "\n" + """
      with timeout of 8 seconds
          tell application "Mail"
              set chosen to selection
              if (count of chosen) < 1 or (count of chosen) > 50 then error "Select 1 to 50 \
      messages" number -1701
              set rows to {}
              repeat with m in chosen
                  set end of rows to my envelope(contents of m)
              end repeat
              return rows
          end tell
      end timeout
      """
  /// Reads Mail account identifiers and display names.
  public static let accounts = """
    with timeout of 8 seconds
        tell application "Mail"
            set resultRows to {}
            repeat with a in accounts
                set end of resultRows to {id of a, name of a, email addresses of a}
            end repeat
            return resultRows
        end tell
    end timeout
    """
  /// Escapes text for use as an AppleScript string literal.
  public static func literal(_ value: String) -> String {
    "\""
      + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(
        of: "\"",
        with: "\\\""
      ).replacingOccurrences(of: "\r", with: "\\r").replacingOccurrences(of: "\n", with: "\\n")
      .replacingOccurrences(of: "\t", with: "\\t") + "\""
  }
  /// Resolves exactly one account-scoped message and rejects stale content.
  public static func lookup(
    _ identity: MessageIdentity,
    action: MailAction = .none,
    expectedSource: String? = nil
  ) throws -> String {
    var operation = "return my envelope(targetMessage)"
    if action != .none {
      guard let expectedSource else { throw IntegrationError.staleMessage }
      let change: String
      switch action {
        case .orangeFlag:
          change = """
            if (flag index of targetMessage) is not -1 and (flag index of targetMessage) is not 1 \
            then error "Existing flag retained" number -1702
            set flag index of targetMessage to 1
            """
        case .orangeBackground:
          change = """
            if (background color of targetMessage) is not none and (background color of \
            targetMessage) is not orange then error "Existing color retained" number -1702
            set background color of targetMessage to orange
            """
        case .moveToJunk, .moveToInbox:
          change =
            try destination(identity, action: action)
            + "\nmove targetMessage to item 1 of destinations"
        case .none: change = ""
      }
      operation =
        "if (source of targetMessage) is not \(literal(expectedSource)) then error \"Message changed\" number -1702\n"
        + change + "\nreturn true"
    }
    return try resolve(identity, operation: operation)
  }
  /// Verifies source and the observed mailbox or annotation without modifying mail.
  public static func verification(
    _ identity: MessageIdentity,
    action: MailAction,
    expectedSource: String
  ) throws -> String {
    let observation: String
    switch action {
      case .moveToInbox, .moveToJunk:
        observation =
          try destination(identity, action: action) + """

            set observedID to id of targetMessage
            set present to (every message of item 1 of destinations whose id is observedID)
            return (count of present) is 1
            """
      case .orangeFlag: observation = "return (flag index of targetMessage) is 1"
      case .orangeBackground: observation = "return (background color of targetMessage) is orange"
      case .none: observation = "return true"
    }
    return try resolve(
      identity,
      operation:
        "if (source of targetMessage) is not \(literal(expectedSource)) then error \"Message changed\" number -1702\n"
        + observation
    )
  }
  private static func destination(_ identity: MessageIdentity, action: MailAction) throws -> String
  {
    guard let account = identity.accountID else { throw IntegrationError.ambiguous }
    let role = action == .moveToJunk ? "junk mailbox" : "inbox"
    return """
      set destinations to {}
      repeat with b in (mailboxes of \(role))
          if (id of account of b) is \(literal(account)) then set end of destinations to contents \
      of b
      end repeat
      if (count of destinations) is not 1 then error "Account mailbox unresolved" number -1701
      """
  }
  static func resolve(_ identity: MessageIdentity, operation: String) throws -> String {
    guard let account = identity.accountID, !account.isEmpty,
      identity.messageID != nil || identity.localID != nil
    else { throw IntegrationError.ambiguous }
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
  public static func recent(limit: Int, mailbox: String = "inbox", offset: Int = 0) -> String {
    let role = ["inbox", "sent mailbox", "junk mailbox"].contains(mailbox) ? mailbox : "inbox"
    return helpers + "\n" + """
      with timeout of 8 seconds
          tell application "Mail"
              set rows to {}
              set candidates to messages of \(role)
              set n to count of candidates
              set firstIndex to \(max(0, offset) + 1)
              set lastIndex to firstIndex + \(max(1, min(maximumPageSize, limit))) - 1
              if lastIndex > n then set lastIndex to n
              if firstIndex <= lastIndex then
                  repeat with i from firstIndex to lastIndex
                      set end of rows to my envelope(item i of candidates)
                  end repeat
              end if
              return rows
          end tell
      end timeout
      """
  }
  /// Reads one account's Inbox and reports its size without modifying messages.
  public static func accountPage(
    accountID: String,
    offset: Int,
    limit: Int,
    role: String = "inbox"
  ) -> String {
    let role = ["inbox", "junk mailbox", "sent mailbox"].contains(role) ? role : "inbox"
    return helpers + "\n" + """
      with timeout of 8 seconds
          tell application "Mail"
              set boxes to {}
              repeat with b in mailboxes of \(role)
                  if (id of account of b) is \(literal(accountID)) then set end of boxes to \
      contents of b
              end repeat
              if (count of boxes) is not 1 then error "Account Inbox unresolved" number -1701
              set rows to {}
              set candidates to messages of item 1 of boxes
              set n to count of candidates
              set firstIndex to \(max(0, offset) + 1)
              set lastIndex to firstIndex + \(max(1, min(maximumPageSize, limit))) - 1
              if lastIndex > n then set lastIndex to n
              if firstIndex <= lastIndex then
                  repeat with i from firstIndex to lastIndex
                      set end of rows to my envelope(item i of candidates)
                  end repeat
              end if
              return {n, rows}
          end tell
      end timeout
      """
  }
}
