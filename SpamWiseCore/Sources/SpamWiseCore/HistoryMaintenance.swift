public import Foundation
import SwiftData

/**
 Keeps each account's Sent correspondence history current with as little reading as possible.

 Maintenance reads each account at most once per interval, so sources sharing a store, such as
 the app and the IMAP daemon, keep separate schedules. Each mailbox keeps a bounded high-water
 mark: the newest Sent message already counted. A run reads from the newest message until it
 reaches the mark, then continues a bounded backfill toward the newest 1,000 messages. Once the
 backfill is complete and the newest page holds the mark, a run reads only that one page. Sent
 pages hold headers only. Inbox history is ingested from the pages the sweeper already reads, so
 maintenance never reads Inbox mail.
 */
public struct HistoryMaintenance: Sendable {
  /// Shortest time between automatic maintenance runs of one account.
  public static let interval: TimeInterval = 900
  private static let stateKey = "history-maintenance-v1"
  private static let headPageSize = 20
  private static let pageSize = 100
  private static let maximumPagesPerRun = 5
  private static let maximumDepth = 1000
  /// Consecutive failures of one backfill page before the cursor steps past it.
  private static let maximumPageFailures = 3
  private let source: any MailSweepSource
  private let store: Store

  /// Creates maintenance over a source's history mailboxes and the store holding the indexes.
  public init(source: any MailSweepSource, store: Store) {
    self.source = source; self.store = store
  }

  /// Whether a mailbox read failure stays local to that mailbox instead of ending the run.
  private static func isIsolated(_ error: any Error) -> Bool {
    !(error is CancellationError) && (error as? IntegrationError) != .permissionDenied
  }

  /**
   Reads new Sent history for those of `accounts` whose interval has elapsed since their
   previous run.

   Each account's progress is saved as soon as its mailbox is read, without replacing progress
   another process saved meanwhile. A mailbox that fails contributes nothing without stopping
   the others.

   - Returns: Whether any account was due.
   - Throws: Cancellation, or a failure when every due mailbox failed or Mail denied permission.
   */
  @discardableResult
  public func runIfDue(for accounts: [MailAccount], now: Date = .now)
    async throws -> Bool
  {
    let state = try await store.read(Self.stateKey, default: MaintenanceState())
    let due = accounts.filter { state.cursors[$0.id]?.isDue(at: now) ?? true }
    guard !due.isEmpty else { return false }
    var failure: (any Error)?, succeeded = false
    for account in due {
      try Task.checkCancellation()
      var cursor = state.cursors[account.id] ?? .init()
      do {
        cursor = try await maintain(account.id, cursor: cursor)
        succeeded = true
      } catch let error where Self.isIsolated(error) {
        failure = error
        cursor.recordFailure(pageSize: Self.pageSize)
      }
      cursor.lastRun = now
      try await save(cursor, for: account.id)
    }
    if let failure, !succeeded { throw failure }
    return true
  }

  /**
   Explicitly imports the newest 1,000 Sent and Inbox messages of every account, merging them
   into the stored indexes.

   Inbox mail contributes only when SpamWise kept it in the Inbox or the user confirmed it there,
   and authenticates its sender only through the account's trusted receiving servers.
   */
  public func importRecent() async throws {
    let eligible = try await StateRepository.historyEligibleInbox(store)
    let trusted = try await AuthenticationTrust.trustedServers(store)
    for account in try await source.sweepAccounts() {
      try Task.checkCancellation()
      let sent = try await recent(account.id, mailbox: .sent)
      let inbox = eligible.isEmpty ? [] : try await recent(account.id, mailbox: .inbox)
      try await HistoryRepository.ingest(
        accountID: account.id,
        sent: sent,
        inbox: inbox,
        eligible: eligible,
        trustedAuthServers: trusted[account.id] ?? [],
        in: store
      )
    }
  }

  /// Replaces one account's cursor, leaving every other account's as currently stored.
  private func save(_ cursor: SentCursor, for accountID: String) async throws {
    try await store.update(Self.stateKey, default: MaintenanceState()) {
      $0.cursors[accountID] = cursor
    }
  }

  private func maintain(_ accountID: String, cursor: SentCursor) async throws -> SentCursor {
    var cursor = cursor, budget = Self.maximumPagesPerRun
    let head = try await readHead(accountID, mark: cursor.mark, budget: &budget)
    try await HistoryRepository.ingest(accountID: accountID, sent: head.envelopes, in: store)
    cursor.advanceHead(to: head)
    guard let offset = cursor.backfillOffset, budget > 0 else { return cursor }
    let backfill = try await readBackfill(accountID, from: offset, budget: &budget)
    try await HistoryRepository.ingest(accountID: accountID, sent: backfill.envelopes, in: store)
    cursor.backfillOffset = backfill.next
    return cursor
  }

  /// Reads from the newest Sent message until reaching `mark`, the budget or the depth limit.
  private func readHead(_ accountID: String, mark: String?, budget: inout Int) async throws
    -> HeadRead
  {
    var read = HeadRead(), offset = 0
    while budget > 0 {
      budget -= 1
      let page = try await source.historyPage(
        accountID: accountID,
        mailbox: .sent,
        offset: offset,
        limit: offset == 0 ? Self.headPageSize : Self.pageSize
      )
      if offset == 0 { read.newest = page.messages.first?.identity.key }
      let unseen = page.messages.prefix { $0.identity.key != mark }
      read.envelopes += unseen
      offset += page.visitedCount
      read.reached = offset
      if mark != nil, unseen.count < page.messages.count { read.foundMark = true; break }
      if page.visitedCount == 0 || offset >= min(page.total, Self.maximumDepth) {
        read.exhausted = true; break
      }
    }
    return read
  }

  private func readBackfill(_ accountID: String, from offset: Int, budget: inout Int)
    async throws -> (envelopes: [MailEnvelope], next: Int?)
  {
    var envelopes: [MailEnvelope] = [], offset = offset
    while budget > 0 {
      budget -= 1
      let page = try await source.historyPage(
        accountID: accountID,
        mailbox: .sent,
        offset: offset,
        limit: Self.pageSize
      )
      envelopes += page.messages
      offset += page.visitedCount
      if page.visitedCount == 0 || offset >= min(page.total, Self.maximumDepth) {
        return (envelopes, nil)
      }
    }
    return (envelopes, offset)
  }

  private func recent(_ accountID: String, mailbox: HistoryMailbox) async throws
    -> [MailEnvelope]
  {
    var envelopes: [MailEnvelope] = [], offset = 0
    while offset < Self.maximumDepth {
      let page: MailPage
      do {
        page = try await source.historyPage(
          accountID: accountID,
          mailbox: mailbox,
          offset: offset,
          limit: Self.pageSize
        )
      } catch let error where offset > 0 && Self.isIsolated(error) {
        break
      }
      envelopes += page.messages
      offset += page.visitedCount
      if page.visitedCount == 0 || offset >= page.total { break }
    }
    return envelopes
  }
}

extension HistoryMaintenance {
  /// Durable maintenance progress shared by every process using the store, by account.
  struct MaintenanceState: Codable, Sendable {
    var cursors: [String: SentCursor] = [:]
  }

  /// One account's Sent history position and schedule.
  struct SentCursor: Codable, Sendable {
    /// Identity key of the newest Sent message already counted.
    var mark: String?
    /// Next backfill position; nil once the backfill reached the depth limit.
    var backfillOffset: Int? = 0
    /// Consecutive failed runs on the current backfill page.
    var failures = 0
    /// Time of the account's latest run, successful or not.
    var lastRun: Date?

    /// Whether the interval has elapsed since the account's latest run.
    func isDue(at now: Date) -> Bool {
      lastRun.map { now.timeIntervalSince($0) >= HistoryMaintenance.interval } ?? true
    }

    /// Moves the mark to the newest message, continuing the backfill after a head that never reached it.
    mutating func advanceHead(to read: HeadRead) {
      if read.exhausted {
        backfillOffset = nil
      } else if !read.foundMark {
        backfillOffset = read.reached
      }
      mark = read.newest ?? mark
      failures = 0
    }

    /// Counts a failed run, stepping past a backfill page that keeps failing.
    mutating func recordFailure(pageSize: Int) {
      failures += 1
      guard failures >= HistoryMaintenance.maximumPageFailures, let offset = backfillOffset
      else { return }
      backfillOffset = offset + pageSize
      failures = 0
    }
  }

  /// Messages read from the newest Sent position.
  struct HeadRead {
    var envelopes: [MailEnvelope] = []
    /// Identity key of the newest readable message.
    var newest: String?
    /// Position after the last page read.
    var reached = 0
    /// Whether the previous mark appeared on a page.
    var foundMark = false
    /// Whether the read reached the end of the mailbox or the depth limit.
    var exhausted = false
  }
}

extension StateRepository {
  /// ``AppState/historyEligibleInbox`` restricted to `envelopes`, read from indexed columns.
  public static func historyEligibleInbox(_ store: Store, among envelopes: [MailEnvelope])
    async throws -> [String: InboxEligibility]
  {
    let keys = envelopes.map(\.identity.key)
    guard !keys.isEmpty else { return [:] }
    let pending = try await load(
      store,
      StateSlices(
        retries: .only(Set(keys)),
        reviewedLabels: .only(Set(envelopes.map(\.identity.contentHash)))
      )
    )
    let superseded = ActionOutcome.superseded.rawValue
    let decisions = try await store.snapshot { context in
      try context.fetch(
        FetchDescriptor<RecordRow>(
          predicate: #Predicate { keys.contains($0.identityKey) && $0.outcome != superseded },
          sortBy: [SortDescriptor(\.date)]
        )
      ).map {
        InboxDecision(
          key: $0.identityKey,
          corrected: $0.correctedLabel.flatMap(MailLabel.init(rawValue:)),
          decided: $0.label.flatMap(MailLabel.init(rawValue:))
        )
      }
    }
    return AppState.historyEligibleInbox(
      decisions: decisions,
      reviewedLabels: pending.reviewedLabels,
      retries: pending.retries
    )
  }
}
