import Foundation
import SpamWiseCore

/// Script conditions raised by the Mail handler library.
///
/// NSAppleScript reports only 16-bit error numbers, so these use a private positive range that
/// system and Mail errors, which are negative, never occupy.
enum MailScriptError: Int, CaseIterable {
  case accountUnresolved = 31_001
  case mailboxUnresolved = 31_002
  case folderUnresolved = 31_003
  case folderLimit = 31_004
  case existingAnnotation = 31_005
  case messageChanged = 31_006
  case messageMissing = 31_007
}

/// Handlers of the compiled Mail library, named as Apple Events address them.
enum MailHandler: String, CaseIterable {
  case accountList = "accountlist"
  case selectedRows = "selectedrows"
  case unifiedPage = "unifiedpage"
  case accountPage = "accountpage"
  case folderList = "folderlist"
  case folderPage = "folderpage"
  case destinationNames = "destinationnames"
  case findMessages = "findmessages"
  case applyAction = "applyaction"
  case reviewState = "reviewstate"
  case observeMessages = "observemessages"
}

/// Bounds and source of the Mail handler library, compiled once and invoked by Apple Event.
enum MailScripts {
  private typealias Failure = MailScriptError
  private typealias Handler = MailHandler
  /// Largest combined source size read by one handler call.
  static let maximumPageBytes = 4_000_000
  /// Largest number of mailbox positions visited by one page.
  static let maximumPageSize = 1000
  /// Largest selection read for a batch correction.
  static let maximumSelectionCount = 50
  /// Largest number of candidates returned when resolving one message, after candidates with the
  /// recorded local ID, then with the expected size.
  static let maximumMatches = 8
  /// Largest number of mailboxes searched for a message anywhere in its account.
  static let maximumSearchedMailboxes = 100
  /// Limit for each individual Apple Event sent to Mail.
  static let eventTimeoutSeconds = 8
  /// What the action handler returns, without changing the message, when it already shows the
  /// requested orange flag or background.
  static let alreadyAnnotated = "already"
  /// Permission and timeout failures that must never be mistaken for an unreadable message.
  static let propagatedFailures = [-1743, -10004, -1712]
  /// `propagatedFailures` as an AppleScript list literal.
  static let propagatedFailureList =
    "{" + propagatedFailures.map(String.init).joined(separator: ", ") + "}"
  /// The complete handler library.
  static let library =
    [accountHandlers, envelopeHandlers, pageHandlers, resolutionHandlers]
    .joined(separator: "\n") + "\n" + folderHandlers + "\n" + destinationHandlers

  private static let accountHandlers = """
    on accountByID(accountID)
        tell application "Mail"
            set found to (every account whose id is accountID)
            if (count of found) is not 1 then error "Account unresolved" number \
    \(Failure.accountUnresolved.rawValue)
            return item 1 of found
        end tell
    end accountByID
    on roleBoxes(roleName, accountID)
        tell application "Mail"
            if roleName is "\(MailboxRole.junk.rawValue)" then
                set candidates to mailboxes of junk mailbox
            else if roleName is "\(MailboxRole.sent.rawValue)" then
                set candidates to mailboxes of sent mailbox
            else
                set candidates to mailboxes of inbox
            end if
            set found to {}
            repeat with b in candidates
                if (id of account of b) is accountID then set end of found to contents of b
            end repeat
            return found
        end tell
    end roleBoxes
    on roleBox(roleName, accountID)
        set found to my roleBoxes(roleName, accountID)
        if (count of found) is not 1 then error "Mailbox unresolved" number \
    \(Failure.mailboxUnresolved.rawValue)
        return item 1 of found
    end roleBox
    on unifiedRole(roleName)
        tell application "Mail"
            if roleName is "\(MailboxRole.junk.rawValue)" then return junk mailbox
            if roleName is "\(MailboxRole.sent.rawValue)" then return sent mailbox
            return inbox
        end tell
    end unifiedRole
    on \(Handler.accountList.rawValue)()
        with timeout of \(eventTimeoutSeconds) seconds
            tell application "Mail"
                set resultRows to {}
                repeat with a in accounts
                    set end of resultRows to {id of a, name of a, email addresses of a}
                end repeat
                return resultRows
            end tell
        end timeout
    end \(Handler.accountList.rawValue)
    """

  private static let envelopeHandlers = """
    on messageBytes(m)
        tell application "Mail"
            try
                return message size of m
            on error number failureNumber
                if \(propagatedFailureList) contains failureNumber then error number failureNumber
                return -1
            end try
        end tell
    end messageBytes
    on identityFields(m)
        tell application "Mail"
            return {id of account of mailbox of m, name of mailbox of m, id of m, message id of m, \
    my messageBytes(m)}
        end tell
    end identityFields
    on readSource(m, fields)
        set byteCount to item 5 of fields
        if byteCount < 0 or byteCount > \(MIMEParser.maximumMessageBytes) then return fields & \
    {false}
        tell application "Mail"
            try
                return fields & {source of m}
            on error number failureNumber
                if \(propagatedFailureList) contains failureNumber then error number failureNumber
                return fields & {false}
            end try
        end tell
    end readSource
    on readHeaders(m, fields)
        tell application "Mail"
            try
                set rawHeaders to all headers of m
            on error number failureNumber
                if \(propagatedFailureList) contains failureNumber then error number failureNumber
                return fields & {false}
            end try
        end tell
        if (count of characters of rawHeaders) > \(MIMEParser.maximumMessageBytes) then return \
    fields & {false}
        return fields & {rawHeaders}
    end readHeaders
    on budgetedEnvelope(m, remainingBytes)
        set fields to my identityFields(m)
        if (item 5 of fields) > remainingBytes then return fields & {false}
        return my readSource(m, fields)
    end budgetedEnvelope
    on readableBytes(rows)
        set used to 0
        repeat with r in rows
            if class of (item 6 of r) is not boolean then set used to used + (item 5 of r)
        end repeat
        return used
    end readableBytes
    on appendMatches(hits, rows)
        repeat with m in hits
            if (count of rows) ≥ \(maximumMatches) then return rows
            set remainingBytes to \(maximumPageBytes) - (my readableBytes(rows))
            set end of rows to my budgetedEnvelope(contents of m, remainingBytes)
        end repeat
        return rows
    end appendMatches
    """

  private static let pageHandlers = """
    on pageRows(candidates, firstIndex, pageLimit, newestFirst, headersOnly)
        set itemCount to count of candidates
        set lastIndex to firstIndex + pageLimit - 1
        if lastIndex > itemCount then set lastIndex to itemCount
        set rows to {}
        set remainingBytes to \(maximumPageBytes)
        if firstIndex ≤ lastIndex then
            repeat with i from firstIndex to lastIndex
                set pageIndex to i
                if not newestFirst then set pageIndex to itemCount - i + 1
                set m to item pageIndex of candidates
                set fields to my identityFields(m)
                if headersOnly then
                    set end of rows to my readHeaders(m, fields)
                else
                    set byteCount to item 5 of fields
                    set readable to byteCount ≥ 0 and byteCount ≤ \(MIMEParser.maximumMessageBytes)
                    if readable and byteCount > remainingBytes and (count of rows) > 0 then ¬
                        exit repeat
                    set end of rows to my readSource(m, fields)
                    if readable then set remainingBytes to remainingBytes - byteCount
                end if
            end repeat
        end if
        return {itemCount, rows}
    end pageRows
    on receivedBetween(targetBox, hasSince, sinceDate, hasBefore, beforeDate)
        tell application "Mail"
            if hasSince and hasBefore then
                return (every message of targetBox whose date received ≥ sinceDate and ¬
                    date received < beforeDate)
            else if hasSince then
                return (every message of targetBox whose date received ≥ sinceDate)
            else if hasBefore then
                return (every message of targetBox whose date received < beforeDate)
            end if
            return messages of targetBox
        end tell
    end receivedBetween
    on isNewestFirst(candidates)
        set itemCount to count of candidates
        if itemCount < 2 then return true
        tell application "Mail"
            return (date received of item 1 of candidates) ≥ ¬
                (date received of item itemCount of candidates)
        end tell
    end isNewestFirst
    on \(Handler.unifiedPage.rawValue)(roleName, firstIndex, pageLimit)
        with timeout of \(eventTimeoutSeconds) seconds
            set targetBox to my unifiedRole(roleName)
            tell application "Mail" to set candidates to messages of targetBox
            return my pageRows(candidates, firstIndex, pageLimit, true, false)
        end timeout
    end \(Handler.unifiedPage.rawValue)
    on \(Handler.accountPage.rawValue)(roleName, accountID, firstIndex, pageLimit, headersOnly, ¬
        hasSince, sinceDate, hasBefore, beforeDate)
        with timeout of \(eventTimeoutSeconds) seconds
            set targetBox to my roleBox(roleName, accountID)
            set candidates to my receivedBetween(targetBox, hasSince, sinceDate, hasBefore, \
    beforeDate)
            set newestFirst to true
            if hasSince or hasBefore then set newestFirst to my isNewestFirst(candidates)
            return my pageRows(candidates, firstIndex, pageLimit, newestFirst, headersOnly)
        end timeout
    end \(Handler.accountPage.rawValue)
    on \(Handler.selectedRows.rawValue)(maximumCount)
        with timeout of \(eventTimeoutSeconds) seconds
            tell application "Mail" to set chosen to selection
            set chosenCount to count of chosen
            if chosenCount < 1 or chosenCount > maximumCount then return {chosenCount, {}}
            set rows to {}
            repeat with m in chosen
                set remainingBytes to \(maximumPageBytes) - (my readableBytes(rows))
                set end of rows to my budgetedEnvelope(contents of m, remainingBytes)
            end repeat
            return {chosenCount, rows}
        end timeout
    end \(Handler.selectedRows.rawValue)
    """

  private static let resolutionHandlers = """
    on namedBoxes(boxes, wantedMailbox)
        set found to {}
        repeat with b in boxes
            set candidate to contents of b
            tell application "Mail"
                considering case
                    if (name of candidate) is wantedMailbox then set end of found to candidate
                end considering
            end tell
        end repeat
        return found
    end namedBoxes
    on searchBoxes(accountID, wantedMailbox)
        set targetAccount to my accountByID(accountID)
        set specialBoxes to (my roleBoxes("\(MailboxRole.inbox.rawValue)", accountID)) & ¬
            (my roleBoxes("\(MailboxRole.junk.rawValue)", accountID))
        if wantedMailbox is not "" then
            set preferred to my namedBoxes(specialBoxes, wantedMailbox)
            if (count of preferred) > 0 then return preferred
        end if
        set walkLimit to \(maximumSearchedMailboxes)
        if wantedMailbox is not "" then set walkLimit to \(maximumFolders)
        tell application "Mail" to set pending to mailboxes of targetAccount
        set visited to {}
        set nextIndex to 1
        repeat while nextIndex ≤ (count of pending) and nextIndex ≤ walkLimit
            set candidate to contents of item nextIndex of pending
            set nextIndex to nextIndex + 1
            set end of visited to candidate
            tell application "Mail" to set pending to pending & (mailboxes of candidate)
        end repeat
        if wantedMailbox is "" then return specialBoxes & visited
        set found to my namedBoxes(visited, wantedMailbox)
        if (count of found) is 0 and nextIndex ≤ (count of pending) then error "Mailbox count \
    limit" number \(Failure.folderLimit.rawValue)
        return found
    end searchBoxes
    on matchesIn(targetBox, wantedID, wantedLocal, wantedBytes)
        tell application "Mail"
            if wantedID is "" then return (every message of targetBox whose id is wantedLocal)
            set exact to {}
            if wantedLocal ≥ 0 then set exact to (every message of targetBox whose message id is \
    wantedID and id is wantedLocal)
            set sized to {}
            if wantedBytes ≥ 0 then set sized to (every message of targetBox whose message id is \
    wantedID and id is not wantedLocal and message size is wantedBytes)
            return exact & sized & (every message of targetBox whose message id is wantedID and id \
    is not wantedLocal and message size is not wantedBytes)
        end tell
    end matchesIn
    on \(Handler.findMessages.rawValue)(accountID, wantedID, wantedLocal, wantedMailbox)
        with timeout of \(eventTimeoutSeconds) seconds
            set rows to {}
            set boxes to my searchBoxes(accountID, wantedMailbox)
            repeat with b in boxes
                set rows to my appendMatches(my matchesIn(contents of b, wantedID, wantedLocal, \
    -1), rows)
                if (count of rows) ≥ \(maximumMatches) then return rows
            end repeat
            return rows
        end timeout
    end \(Handler.findMessages.rawValue)
    on sizedMatches(targetBox, wantedBytes)
        if wantedBytes < 0 then return {}
        tell application "Mail" to return (every message of targetBox whose message size is \
    wantedBytes)
    end sizedMatches
    on \(Handler.observeMessages.rawValue)(accountID, roleName, wantedID, wantedBytes)
        with timeout of \(eventTimeoutSeconds) seconds
            set targetBox to my roleBox(roleName, accountID)
            if wantedID is "" then return my appendMatches(my sizedMatches(targetBox, \
    wantedBytes), {})
            return my appendMatches(my matchesIn(targetBox, wantedID, -1, wantedBytes), {})
        end timeout
    end \(Handler.observeMessages.rawValue)
    on exactMessage(accountID, mailboxName, wantedLocal, wantedID, expectedBytes)
        set found to {}
        set boxes to my searchBoxes(accountID, mailboxName)
        repeat with b in boxes
            set found to found & (my matchesIn(contents of b, "", wantedLocal, -1))
        end repeat
        if (count of found) is not 1 then error "Message left its mailbox" number \
    \(Failure.messageMissing.rawValue)
        set m to item 1 of found
        tell application "Mail"
            considering case
                if (id of account of mailbox of m) is not accountID or ¬
                    (name of mailbox of m) is not mailboxName then error "Message left its \
    mailbox" number \(Failure.messageMissing.rawValue)
                if wantedID is not "" and (message id of m) is not wantedID then error ¬
                    "Message changed" number \(Failure.messageChanged.rawValue)
            end considering
            if (message size of m) is not expectedBytes then error "Message changed" number \
    \(Failure.messageChanged.rawValue)
        end tell
        return m
    end exactMessage
    \(actionHandler)
    """

  private static let actionHandler = """
    on \(Handler.applyAction.rawValue)(commandName, accountID, mailboxName, wantedLocal, wantedID, \
    expectedBytes)
        with timeout of \(eventTimeoutSeconds) seconds
            if commandName is "\(MailCommand.moveToJunk.rawValue)" or ¬
                commandName is "\(MailCommand.markRead.rawValue)" then
                set destination to my roleBox("\(MailboxRole.junk.rawValue)", accountID)
            else if commandName is "\(MailCommand.moveToInbox.rawValue)" then
                set destination to my roleBox("\(MailboxRole.inbox.rawValue)", accountID)
            end if
            set m to my exactMessage(accountID, mailboxName, wantedLocal, wantedID, expectedBytes)
            tell application "Mail"
                if commandName is "\(MailCommand.moveToJunk.rawValue)" or ¬
                    commandName is "\(MailCommand.moveToInbox.rawValue)" then
                    considering case
                        if (name of mailbox of m) is (name of destination) then return true
                    end considering
                    move m to destination
                    return true
                else if commandName is "\(MailCommand.orangeFlag.rawValue)" then
                    if (flag index of m) is 1 then return "\(alreadyAnnotated)"
                    if (flag index of m) is not -1 then error ¬
                        "Existing flag retained" number \(Failure.existingAnnotation.rawValue)
                    set flag index of m to 1
                    return my showsReview(commandName, m)
                else if commandName is "\(MailCommand.orangeBackground.rawValue)" then
                    if (background color of m) is orange then return "\(alreadyAnnotated)"
                    if (background color of m) is not none then error "Existing color retained" \
    number \(Failure.existingAnnotation.rawValue)
                    set background color of m to orange
                    return my showsReview(commandName, m)
                else if commandName is "\(MailCommand.clearOrangeFlag.rawValue)" then
                    if (flag index of m) is 1 then set flag index of m to -1
                    return my showsReview(commandName, m)
                else if commandName is "\(MailCommand.clearOrangeBackground.rawValue)" then
                    if (background color of m) is orange then set background color of m to none
                    return my showsReview(commandName, m)
                else if commandName is "\(MailCommand.markRead.rawValue)" then
                    considering case
                        if (name of mailbox of m) is not (name of destination) then error ¬
                            "Message left Junk" number \(Failure.messageMissing.rawValue)
                    end considering
                    set read status of m to true
                    return (read status of m) is true
                else if commandName is "\(MailCommand.open.rawValue)" then
                    open m
                    activate
                    return true
                end if
            end tell
            return false
        end timeout
    end \(Handler.applyAction.rawValue)
    on showsReview(commandName, m)
        tell application "Mail"
            if commandName is "\(MailCommand.orangeFlag.rawValue)" then return ¬
                (flag index of m) is 1
            if commandName is "\(MailCommand.orangeBackground.rawValue)" then return ¬
                (background color of m) is orange
            if commandName is "\(MailCommand.clearOrangeFlag.rawValue)" then return ¬
                (flag index of m) is not 1
            if commandName is "\(MailCommand.clearOrangeBackground.rawValue)" then return ¬
                (background color of m) is not orange
        end tell
        return false
    end showsReview
    on \(Handler.reviewState.rawValue)(commandName, accountID, mailboxName, wantedLocal, wantedID, \
    expectedBytes)
        with timeout of \(eventTimeoutSeconds) seconds
            set m to my exactMessage(accountID, mailboxName, wantedLocal, wantedID, expectedBytes)
            return my showsReview(commandName, m)
        end timeout
    end \(Handler.reviewState.rawValue)
    """
}
