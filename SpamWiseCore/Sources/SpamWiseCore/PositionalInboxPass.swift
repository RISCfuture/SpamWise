import Foundation

/**
 One automatic pass over an Inbox whose pages are addressed by position from the newest message.

 Each pass reads pages from the newest message while each page holds a message new to the
 processed-message index, so mail delivered during the pass that shifts already processed
 messages onto a page does not end it early. It then continues a backfill toward the account's
 start boundary that restarts after reaching it or the newest 10,000 messages. A burst larger
 than one pass's page budget continues from where the pass stopped. Mail received before the
 boundary is never read, so it cannot be classified or acted on automatically.

 A page read that times out ends the pass and reports its position, keeping the progress of the
 pages before it.
 */
public struct PositionalInboxPass: Sendable {
  /// Reads the page at a position with at most the given number of messages.
  public typealias PageReader = @Sendable (_ offset: Int, _ limit: Int) async throws -> MailPage

  private static let maximumPagesPerRun = 5
  private static let maximumBackfillDepth = 10_000
  private let request: InboxPassRequest
  private let processing: InboxPageProcessor
  private let read: PageReader

  /// Creates a pass that reads pages with `read` and hands each to `processing`.
  public init(
    request: InboxPassRequest,
    processing: @escaping InboxPageProcessor,
    read: @escaping PageReader
  ) {
    self.request = request; self.processing = processing; self.read = read
  }

  /// Processes new mail from the newest position, then backfill pages.
  public func run() async throws -> InboxTraversal {
    var budget = Self.maximumPagesPerRun
    let head = try await drain(from: 0, budget: &budget)
    let body = try await backfill(after: head, budget: &budget)
    let depth = min(head.total, Self.maximumBackfillDepth)
    return InboxTraversal(
      end: body.stalledOffset != nil || body.end < depth ? body.end : 0,
      total: head.total,
      visited: body.visited,
      unavailable: body.unavailable,
      interrupted: body.interrupted,
      stalledOffset: body.stalledOffset
    )
  }

  /// The segment that determines the next cursor: the head itself, or the backfill after it.
  private func backfill(after head: Segment, budget: inout Int) async throws -> Segment {
    let saved = request.resumeOffset
    if head.interrupted { return head }
    if head.stalledOffset != nil { return head.end > 0 ? head : head.keepingCursor(at: saved) }
    if head.unfinished || saved == 0 || saved >= head.total { return head }
    guard budget > 0 else { return Segment(end: saved) }
    return try await drain(from: saved, budget: &budget)
  }

  /// Reads consecutive pages from `offset` while each page holds a new message.
  private func drain(from offset: Int, budget: inout Int) async throws -> Segment {
    var segment = Segment(end: offset)
    while budget > 0 {
      budget -= 1
      let page: MailPage
      do {
        page = try await read(segment.end, request.pageLimit)
      } catch IntegrationError.timedOut {
        segment.stalledOffset = segment.end
        break
      }
      let processed = try await processing(page)
      let position = segment.end + page.visitedCount
      segment.end = max(offset, position - processed.records.count(where: \.mayHaveLeftMailbox))
      segment.total = page.total
      segment.visited += page.visitedCount
      segment.unavailable += page.unavailableCount
      guard processed.completed else { segment.interrupted = true; break }
      segment.unfinished =
        processed.records.contains { !$0.deferredBySpendingLimit } && position < page.total
      guard segment.unfinished else { break }
    }
    return segment
  }
}

extension PositionalInboxPass {
  /// Positions covered by consecutive pages.
  private struct Segment {
    /// Position of the next unread page, adjusted for messages moved out of the Inbox.
    var end: Int
    var total = 0
    var visited = 0
    var unavailable = 0
    /// Whether the page budget ran out while the last page still held new messages.
    var unfinished = false
    var interrupted = false
    var stalledOffset: Int?

    /// This segment's counts with the cursor left at `offset`.
    func keepingCursor(at offset: Int) -> Self {
      var segment = self
      segment.end = offset
      return segment
    }
  }
}

extension DecisionRecord {
  /// Whether this record's move may have taken its message out of its mailbox, counting uncertain moves.
  var mayHaveLeftMailbox: Bool {
    [.moveToJunk, .moveToInbox].contains(decision.action)
      && [.requested, .applied, .failed].contains(outcome)
  }
}
