import Foundation
public import SpamWiseCore

extension AppleMailAdapter {
  /// Sent pages read only headers, so they hold more messages per script than Inbox pages.
  private static let sentHistoryPageSize = 100
  /// Inbox pages read full sources of up to 2 MB each within one script timeout.
  private static let inboxHistoryPageSize = 20
  private static let historyImportLimit = 1000
  /// Consecutive failures of one incremental page before the cursor steps past it.
  private static let maximumHistoryPageFailures = 3

  private static func historyPageSize(role: MailboxRole) -> Int {
    role == .sent ? sentHistoryPageSize : inboxHistoryPageSize
  }
  /// Whether a mailbox read failure stays local to that mailbox instead of ending the import.
  private static func isIsolated(_ error: any Error) -> Bool {
    !(error is CancellationError) && (error as? IntegrationError) != .permissionDenied
  }
  private static func recording(
    sent: [MailEnvelope],
    inbox: [MailEnvelope],
    eligibleInbox: [String: InboxEligibility],
    into index: HistoryIndex,
    trustedAuthServers: Set<String>
  ) -> HistoryIndex {
    var index = index
    index.availability = .partial; index.updatedAt = .now
    for envelope in sent {
      guard let headers = try? MIMEParser().headers(envelope.raw),
        index.importedIDs.insert("sent:" + envelope.identity.key).inserted
      else { continue }
      index.recordSent(headers: headers)
    }
    for envelope in inbox {
      guard let eligibility = eligibleInbox[envelope.identity.key],
        let message = try? MIMEParser().parse(envelope.raw)
      else { continue }
      index.recordReceived(
        message,
        identityKey: envelope.identity.key,
        eligibility: eligibility,
        trustedAuthServers: trustedAuthServers
      )
    }
    return index
  }
  /// Imports bounded Sent history; Inbox mail needs an explicit eligibility set.
  public func importHistory() async throws -> [String: HistoryIndex] {
    try await importHistory(previous: [:], eligibleInbox: [:])
  }
  /**
   Adds only unseen messages to each account's history snapshot.

   Sent mail contributes only its headers, and Inbox mail is read only when some message is
   eligible. Unreadable or oversized messages are skipped, and an incremental import advances
   each account's cursor past every visited position. A mailbox page that fails contributes
   nothing, without stopping other mailboxes or accounts. An incremental cursor stays on a failed
   page until it fails three times in a row, then steps past it, even when that failure makes the
   import throw; a full import keeps the pages it read before the failure. The import throws only
   when no mailbox could be read or Mail denies permission.

   - Parameters:
     - eligibleInbox: Inbox messages SpamWise already classified or the user confirmed as Inbox,
       by identity key. No other Inbox message contributes history, and only confirmed receipts
       can authenticate their sender.
     - trustedAuthServers: Each account's receiving servers, by account identifier, whose
       authentication results a receipt must pass.
     - incremental: Reads one page per mailbox instead of the most recent 1,000 messages.
   */
  public func importHistory(
    previous: [String: HistoryIndex],
    eligibleInbox: [String: InboxEligibility],
    trustedAuthServers: [String: Set<String>] = [:],
    incremental: Bool = false
  ) async throws -> [String: HistoryIndex] {
    var indexes = previous, advanced: [String: Int] = [:], failure: (any Error)?, readAny = false
    for account in try await accounts() {
      var reads: [MailboxRole: [MailEnvelope]] = [:]
      for role: MailboxRole in eligibleInbox.isEmpty ? [.sent] : [.sent, .inbox] {
        do {
          reads[role] = try await historyMessages(
            account.id,
            role: role,
            incremental: incremental,
            advancing: &advanced
          ) { role == .sent || eligibleInbox[$0.identity.key] != nil }
        } catch let error where Self.isIsolated(error) {
          failure = error
        }
      }
      guard !reads.isEmpty else { continue }
      readAny = true
      indexes[account.id] = Self.recording(
        sent: reads[.sent] ?? [],
        inbox: reads[.inbox] ?? [],
        eligibleInbox: eligibleInbox,
        into: indexes[account.id] ?? HistoryIndex(),
        trustedAuthServers: trustedAuthServers[account.id] ?? []
      )
    }
    pageOffsets.merge(advanced) { $1 }
    if let failure, !readAny { throw failure }
    return indexes
  }
  /// Reads one page, or the most recent messages, keeping only those `isIncluded` accepts.
  ///
  /// An incremental read stores its next cursor position in `advanced` for the caller to commit.
  private func historyMessages(
    _ accountID: String,
    role: MailboxRole,
    incremental: Bool,
    advancing advanced: inout [String: Int],
    where isIncluded: (MailEnvelope) -> Bool
  ) async throws -> [MailEnvelope] {
    guard incremental else {
      return try await recentHistory(accountID, role: role, where: isIncluded)
    }
    let cursor = "history-\(role.rawValue)-\(accountID)"
    let offset = pageOffsets[cursor, default: 0]
    let page: MailPage
    do {
      page = try await historyPage(accountID, role: role, offset: offset)
    } catch let error where Self.isIsolated(error) {
      if recordHistoryPageFailure(cursor) {
        advanced[cursor] = offset + Self.historyPageSize(role: role)
      }
      throw error
    }
    historyPageFailures[cursor] = nil
    let next = offset + page.visitedCount
    advanced[cursor] = page.visitedCount == 0 || next >= page.total ? 0 : next
    return page.messages.filter(isIncluded)
  }
  private func recentHistory(
    _ accountID: String,
    role: MailboxRole,
    where isIncluded: (MailEnvelope) -> Bool
  ) async throws -> [MailEnvelope] {
    var messages: [MailEnvelope] = [], offset = 0
    while offset < Self.historyImportLimit {
      let page: MailPage
      do {
        page = try await historyPage(accountID, role: role, offset: offset)
      } catch let error where offset > 0 && Self.isIsolated(error) {
        break
      }
      messages += page.messages.filter(isIncluded)
      offset += page.visitedCount
      if page.visitedCount == 0 || offset >= page.total { break }
    }
    return messages
  }
  /// Counts a failed read of the cursor's page, returning whether the cursor should step past it.
  private func recordHistoryPageFailure(_ cursor: String) -> Bool {
    let failures = historyPageFailures[cursor, default: 0] + 1
    historyPageFailures[cursor] = failures < Self.maximumHistoryPageFailures ? failures : nil
    return failures >= Self.maximumHistoryPageFailures
  }
  /// An account without a uniquely resolvable mailbox for the role contributes no history.
  private func historyPage(_ accountID: String, role: MailboxRole, offset: Int) async throws
    -> MailPage
  {
    let limit = Self.historyPageSize(role: role)
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
