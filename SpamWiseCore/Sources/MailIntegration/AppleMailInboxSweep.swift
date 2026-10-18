public import Foundation
public import SpamWiseCore

/**
 One automatic pass over an Apple Mail account's Inbox.

 Each pass reads pages from the newest message while each page holds a message new to the
 processed-message index, so mail delivered during the pass that shifts already processed
 messages onto a page does not end it early. It then continues a backfill toward the account's
 start boundary that restarts after reaching it or the newest 10,000 messages. A burst larger
 than one pass's page budget continues from where the pass stopped. Mail received before the
 boundary is never read, so it cannot be classified or acted on automatically.
 */
public struct AppleMailInboxSweep: Sendable {
  private static let maximumPagesPerRun = 5
  private static let maximumBackfillDepth = 10_000
  /// The Mail client that supplies pages and performs actions.
  public let adapter: AppleMailAdapter
  /// The pipeline that classifies, persists and dispatches each message.
  public let pipeline: Pipeline
  /// Durable storage for scan progress and the processed-message index.
  public let store: Store

  /// Creates a sweep over the supplied adapter, pipeline and store.
  public init(adapter: AppleMailAdapter, pipeline: Pipeline, store: Store) {
    self.adapter = adapter; self.pipeline = pipeline; self.store = store
  }

  /**
   Processes new Inbox mail, then backfill pages, for one account.

   The backfill cursor stays in place when filtering is paused, because a paused batch can
   stop before the end of its page.

   - Parameters:
     - account: The account to scan.
     - dryRun: Whether to suppress mail actions regardless of settings.
     - limit: Maximum messages per page.
     - firstSeen: The start boundary recorded for an account that has none.
     - progress: Called after each processed message with the running count and page size.
   */
  public func run(
    account: MailAccount,
    dryRun: Bool,
    limit: Int,
    firstSeen: Date = .now,
    progress: @escaping @Sendable (Int, Int) async -> Void = { _, _ in }
  ) async throws {
    let health = try await MailHealthRepository.load(store, key: account.id)
    let pass = Pass(
      sweep: self,
      account: account,
      start: health?.inboxStart ?? firstSeen,
      dryRun: dryRun,
      limit: limit,
      progress: progress
    )
    try await MailHealthRepository.update(store, accountID: account.id, name: account.name) {
      $0.inboxStart = pass.start; $0.lastAttempt = .now
    }
    var budget = Self.maximumPagesPerRun
    let head = try await pass.drain(from: 0, budget: &budget)
    let saved = health?.nextOffset ?? 0
    let traversal: Traversal
    if head.unfinished || saved == 0 || saved >= head.total {
      traversal = head
    } else if budget == 0 {
      traversal = Traversal(end: saved)
    } else {
      traversal = try await pass.drain(from: saved, budget: &budget)
    }
    try Task.checkCancellation()
    guard try await !StateRepository.load(store, StateSlices()).settings.paused else { return }
    let end = traversal.end < min(head.total, Self.maximumBackfillDepth) ? traversal.end : 0
    try await MailHealthRepository.update(store, accountID: account.id, name: account.name) {
      $0.complete(
        through: end,
        visited: traversal.visited,
        total: head.total,
        unavailable: traversal.unavailable
      )
    }
  }
}

extension AppleMailInboxSweep {
  /// Positions covered by consecutive pages.
  struct Traversal {
    /// Position of the next unread page, adjusted for messages moved out of the Inbox.
    var end: Int
    var total = 0
    var visited = 0
    var unavailable = 0
    /// Whether the page budget ran out while the last page still held new messages.
    var unfinished = false
  }

  struct Pass {
    let sweep: AppleMailInboxSweep
    let account: MailAccount
    let start: Date
    let dryRun: Bool
    let limit: Int
    let progress: @Sendable (Int, Int) async -> Void

    /// Messages a page's actions moved out of the Inbox, conservatively including uncertain moves.
    private static func departures(_ records: [DecisionRecord]) -> Int {
      records.count {
        $0.decision.action == .moveToJunk && [.requested, .applied, .failed].contains($0.outcome)
      }
    }

    /// Reads consecutive pages from `offset` while each page holds a new message.
    func drain(from offset: Int, budget: inout Int) async throws -> Traversal {
      var traversal = Traversal(end: offset)
      while budget > 0 {
        budget -= 1
        let page = try await sweep.adapter.inboxPage(
          accountID: account.id,
          offset: traversal.end,
          limit: limit,
          since: start
        )
        let records = try await process(page)
        let position = traversal.end + page.visitedCount
        traversal.end = max(offset, position - Self.departures(records))
        traversal.total = page.total
        traversal.visited += page.visitedCount
        traversal.unavailable += page.unavailableCount
        traversal.unfinished = !records.isEmpty && position < page.total
        guard traversal.unfinished else { break }
      }
      return traversal
    }

    private func process(_ page: MailPage) async throws -> [DecisionRecord] {
      let total = page.messages.count
      return try await sweep.pipeline.processBatch(
        page.messages,
        adapter: sweep.adapter,
        dryRun: dryRun,
        skipsSettled: true
      ) { count in await progress(count, total) }
    }
  }
}
