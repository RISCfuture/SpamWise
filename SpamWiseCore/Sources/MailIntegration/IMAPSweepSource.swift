import Foundation
public import SpamWiseCore

extension IMAPAdapter: MailSweepSource {
  /// The one account this connection serves.
  public func sweepAccounts() throws -> [MailAccount] {
    [MailAccount(id: accountID, name: configuration.username + "@" + configuration.host)]
  }

  /**
   Reads new mail above the UID high-water mark, then one backfill page, as one page.

   The sweep cursor is saved in the adapter's validation store, and only once the page was
   processed completely; the request's position is unused because UIDs order IMAP mail. Every
   pass completes a traversal of its own.
   */
  public func sweepInbox(
    of _: MailAccount,
    _ request: InboxPassRequest,
    processing: @escaping InboxPageProcessor
  ) async throws -> InboxTraversal {
    let sweep = try await nextInboxSweep(limit: request.pageLimit, cursorStore: validations)
    let count = sweep.messages.count
    let page = MailPage(messages: sweep.messages, total: count, visitedCount: count)
    let processed = try await processing(page)
    guard processed.completed else {
      return InboxTraversal(end: 0, total: count, visited: count, interrupted: true)
    }
    try await commit(sweep, cursorStore: validations)
    return InboxTraversal(end: 0, total: count, visited: count)
  }

  /// The newest Inbox messages, within the adapter's size budget.
  public func recentInboxPage(accountID _: String, limit: Int) async throws -> MailPage {
    let messages = try await recentMessages(limit: limit)
    return MailPage(messages: messages, total: messages.count, visitedCount: messages.count)
  }

  /// Reads one page of the Sent mailbox or Inbox, newest first; no Sent role yields an empty page.
  public func historyPage(
    accountID _: String,
    mailbox: HistoryMailbox,
    offset: Int,
    limit: Int
  ) async throws -> MailPage {
    let account = self.accountID
    return try await withSession { session in
      let name: String
      switch mailbox {
        case .inbox: name = "INBOX"
        case .sent:
          guard let sent = try await Self.roles(session: session).sent else {
            return MailPage(messages: [], total: 0, visitedCount: 0)
          }
          name = sent
      }
      let selected = try await Self.select(name, writable: false, session: session)
      let read = try await Self.messages(
        mailbox: name,
        account: account,
        limit: limit,
        session: session,
        offset: offset,
        selection: selected
      )
      let end = read.nextOffset == 0 ? selected.count : read.nextOffset
      return MailPage(
        messages: read.envelopes,
        total: selected.count,
        visitedCount: max(read.envelopes.count, end - offset)
      )
    }
  }
}
