extension MailScripts {
  /// Deepest mailbox nesting listed or addressed by path.
  static let maximumFolderDepth = 16
  /// Largest number of mailboxes listed across all accounts.
  static let maximumFolders = 1000
  /// Longest mailbox name accepted in a configured path.
  static let maximumFolderNameBytes = 1024

  static let folderHandlers = """
    on listBoxes(boxes, accountID, prefixNames, depth)
        set rows to {}
        if (count of boxes) is 0 then return rows
        if depth ≥ \(maximumFolderDepth) then error "Mailbox nesting limit" number \
    \(MailScriptError.folderLimit.rawValue)
        tell application "Mail"
            repeat with b in boxes
                set names to prefixNames & {name of b}
                set end of rows to {accountID, names}
                set rows to rows & my listBoxes(mailboxes of b, accountID, names, depth + 1)
                if (count of rows) > \(maximumFolders) then error "Mailbox count limit" number \
    \(MailScriptError.folderLimit.rawValue)
            end repeat
        end tell
        return rows
    end listBoxes
    on \(MailHandler.folderList.rawValue)()
        with timeout of \(eventTimeoutSeconds) seconds
            tell application "Mail"
                set rows to {}
                repeat with a in accounts
                    set rows to rows & my listBoxes(mailboxes of a, id of a, {}, 0)
                    if (count of rows) > \(maximumFolders) then error "Mailbox count limit" number \
    \(MailScriptError.folderLimit.rawValue)
                end repeat
                return rows
            end tell
        end timeout
    end \(MailHandler.folderList.rawValue)
    on folderBox(accountID, wantedNames)
        tell application "Mail"
            set accountMatches to (every account whose id is accountID)
            if (count of accountMatches) is not 1 then error "Account unresolved" number \
    \(MailScriptError.folderUnresolved.rawValue)
            set boxes to mailboxes of item 1 of accountMatches
            repeat with wantedName in wantedNames
                set foundBoxes to {}
                repeat with b in boxes
                    considering case
                        if (name of b) is (contents of wantedName) then set end of foundBoxes to \
    contents of b
                    end considering
                end repeat
                if (count of foundBoxes) is not 1 then error "Folder unresolved" number \
    \(MailScriptError.folderUnresolved.rawValue)
                set targetBox to item 1 of foundBoxes
                set boxes to mailboxes of targetBox
            end repeat
            return targetBox
        end tell
    end folderBox
    on \(MailHandler.folderPage.rawValue)(accountID, wantedNames, firstIndex, pageLimit, filtered, \
    sinceDate)
        with timeout of \(eventTimeoutSeconds) seconds
            set targetBox to my folderBox(accountID, wantedNames)
            tell application "Mail"
                if filtered then
                    set candidates to (every message of targetBox whose date received ≥ sinceDate)
                else
                    set candidates to messages of targetBox
                end if
            end tell
            return my pageRows(candidates, firstIndex, pageLimit, true, false)
        end timeout
    end \(MailHandler.folderPage.rawValue)
    """
}
