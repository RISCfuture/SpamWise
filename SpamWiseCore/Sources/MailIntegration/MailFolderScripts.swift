public import Foundation
public import SpamWiseCore

extension MailScripts {
  private static let maximumFolderDepth = 16
  private static let maximumFolderNameBytes = 1024
  /// Enumerates bounded account-scoped paths without reading message bodies.
  public static let folders = """
    on listBoxes(boxes, accountID, prefixNames, depth)
        if depth > 16 then error "Mailbox nesting limit" number -1702
        set rows to {}
        tell application "Mail"
            repeat with b in boxes
                set names to prefixNames & {name of b}
                set end of rows to {accountID, names}
                set rows to rows & my listBoxes(mailboxes of b, accountID, names, depth + 1)
                if (count of rows) > 1000 then error "Mailbox count limit" number -1702
            end repeat
        end tell
        return rows
    end listBoxes
    with timeout of 8 seconds
        tell application "Mail"
            set rows to {}
            repeat with a in accounts
                set rows to rows & my listBoxes(mailboxes of a, id of a, {}, 0)
                if (count of rows) > 1000 then error "Mailbox count limit" number -1702
            end repeat
            return rows
        end tell
    end timeout
    """
  /// Reads a bounded exact-path page, optionally restricted by received date.
  public static func folderPage(_ folder: MailFolder, offset: Int, limit: Int, since: Date? = nil)
    throws -> String
  {
    guard !folder.accountID.isEmpty, !folder.path.isEmpty, folder.path.count <= maximumFolderDepth,
      folder.path.allSatisfy({ !$0.isEmpty && $0.utf8.count <= maximumFolderNameBytes })
    else { throw IntegrationError.ambiguous }
    let names = "{" + folder.path.map(literal).joined(separator: ", ") + "}"
    let candidates =
      since == nil
      ? "messages of targetBox" : "(every message of targetBox whose date received ≥ sinceDate)"
    return helpers + "\n" + """
      with timeout of 8 seconds
          tell application "Mail"
              set accountMatches to (every account whose id is \(literal(folder.accountID)))
              if (count of accountMatches) is not 1 then error "Account unresolved" number -1701
              set boxes to mailboxes of item 1 of accountMatches
              repeat with wantedName in \(names)
                  set foundBoxes to {}
                  repeat with b in boxes
                      if name of b is (contents of wantedName) then set end of foundBoxes to \
      contents of b
                  end repeat
                  if (count of foundBoxes) is not 1 then error "Folder unresolved" number -1701
                  set targetBox to item 1 of foundBoxes
                  set boxes to mailboxes of targetBox
              end repeat
              \(since.map(dateBoundary) ?? "")
              set candidates to \(candidates)
              set n to count of candidates
              set firstIndex to \(max(0, offset) + 1)
              set lastIndex to firstIndex + \(max(1, min(1000, limit))) - 1
              if lastIndex > n then set lastIndex to n
              set rows to {}
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
  private static func dateBoundary(_ date: Date) -> String {
    let parts = Calendar.current.dateComponents(
      [.year, .month, .day, .hour, .minute, .second],
      from: date
    )
    let seconds = (parts.hour ?? 0) * 3600 + (parts.minute ?? 0) * 60 + (parts.second ?? 0)
    return """
      set sinceDate to current date
      set day of sinceDate to 1
      set year of sinceDate to \(parts.year ?? 2000)
      set month of sinceDate to \(parts.month ?? 1)
      set day of sinceDate to \(parts.day ?? 1)
      set time of sinceDate to \(seconds)
      """
  }
}
