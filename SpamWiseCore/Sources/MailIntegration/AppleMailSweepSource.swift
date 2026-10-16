public import Foundation
public import SpamWiseCore

extension AppleMailAdapter: PositionalInboxSource {
  /// Every account Mail reports.
  public func sweepAccounts() async throws -> [MailAccount] { try await accounts() }

  /// Reads an Inbox page received on or after `since`, newest first.
  public func inboxSweepPage(accountID: String, offset: Int, limit: Int, since: Date?)
    async throws -> MailPage
  {
    try await inboxPage(accountID: accountID, offset: offset, limit: limit, since: since)
  }

  /**
   Reads one history page; Sent pages hold only headers.

   An account without a uniquely resolvable mailbox for the role returns an empty page.
   */
  public func historyPage(
    accountID: String,
    mailbox: HistoryMailbox,
    offset: Int,
    limit: Int
  ) async throws -> MailPage {
    let role: MailboxRole = mailbox == .sent ? .sent : .inbox
    let request = MailRequest.accountPage(
      role: role,
      accountID: accountID,
      offset: offset,
      limit: limit,
      headersOnly: role == .sent
    )
    do {
      return try Self.decodePage(
        await invoke(request),
        accountID: accountID,
        offset: offset,
        limit: limit
      )
    } catch IntegrationError.mailboxUnresolved {
      return MailPage(messages: [], total: 0, visitedCount: 0)
    }
  }
}
