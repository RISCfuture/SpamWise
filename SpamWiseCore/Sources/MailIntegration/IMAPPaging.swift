import Foundation
import NIOIMAP
import SpamWiseCore

extension IMAPAdapter {
  private static let maximumPageSize = 100
  private static let maximumPageBytes = 4_000_000
  private static let maximumArrivalPages = 5
  private static let maximumArrivalScanPages = 20
  private static let maximumBackfillDepth = 10_000

  static func messages(
    mailbox: String,
    account: String,
    limit: Int,
    session: IMAPSession,
    offset: Int = 0,
    selection: IMAPMailboxSelection? = nil,
    aboveUID boundary: Int = 0,
    belowUID ceiling: Int = .max
  ) async throws -> (envelopes: [MailEnvelope], nextOffset: Int) {
    guard limit > 0 else { return ([], offset) }
    let selected: IMAPMailboxSelection
    if let selection {
      selected = selection
    } else {
      selected = try await select(mailbox, writable: false, session: session)
    }
    guard !selected.isEmpty else { return ([], 0) }
    let last = max(1, selected.count - offset)
    let first = max(1, last - min(limit, maximumPageSize) + 1)
    let metadata = try await metadata(
      range: first...last,
      limit: min(limit, maximumPageSize),
      session: session
    )
    var envelopes: [MailEnvelope] = []
    var total = 0, nextOffset = selected.count - first + 1
    for row in metadata {
      guard row.uid > boundary else { return (envelopes, 0) }
      guard row.uid < ceiling, row.size <= MIMEParser.maximumMessageBytes else { continue }
      guard row.size <= maximumPageBytes - total, envelopes.isEmpty || !session.isPastFetchDeadline
      else {
        nextOffset = selected.count - row.sequence
        break
      }
      let fetched: Data?
      do {
        fetched = try await fetch(uid: row.uid, session: session)
      } catch IMAPError.limitExceeded {
        nextOffset = selected.count - row.sequence + 1
        break
      }
      guard let raw = fetched else { continue }
      guard raw.count <= maximumPageBytes - total else {
        nextOffset = selected.count - row.sequence
        break
      }
      total += raw.count
      envelopes.append(
        envelope(raw, account: account, uid: row.uid, mailbox: mailbox, validity: selected.validity)
      )
    }
    return (envelopes, nextOffset >= selected.count ? 0 : nextOffset)
  }

  static func sweepInbox(
    account: String,
    limit: Int,
    cursor: IMAPSweepCursor,
    session: IMAPSession
  ) async throws -> (envelopes: [MailEnvelope], cursor: IMAPSweepCursor) {
    let selected = try await select("INBOX", writable: false, session: session)
    guard let boundary = cursor.boundary(validity: selected.validity) else {
      let newest = try await newestUID(selected, session: session)
      return (
        [],
        IMAPSweepCursor(validity: selected.validity, boundaryUID: newest, highWaterUID: newest)
      )
    }
    let arrivals = try await arrivals(
      account: account,
      limit: limit,
      above: cursor.highWaterUID ?? boundary,
      selection: selected,
      session: session
    )
    var next = IMAPSweepCursor(
      offset: cursor.currentOffset(validity: selected.validity, count: selected.count),
      validity: selected.validity,
      boundaryUID: boundary,
      highWaterUID: arrivals.highWater,
      backfill: cursor.backfill
    )
    if let overflow = arrivals.overflow {
      next.backfill = next.backfill?.merged(with: overflow) ?? overflow
      next.offset = arrivals.scanned
      return (arrivals.envelopes, next)
    }
    guard arrivals.caughtUp, !session.isPastFetchDeadline else { return (arrivals.envelopes, next) }
    let backfilled = try await backfillPage(
      account: account,
      limit: limit,
      cursor: &next,
      from: max(next.offset, arrivals.scanned),
      selection: selected,
      session: session
    )
    return (arrivals.envelopes + backfilled, next)
  }

  /**
   Reads one page of the cursor's pending backfill from position `start`, counted from the newest
   message, and advances the cursor past it.

   The ceiling drops to the oldest message the page read, so mail that later arrivals push into
   the page's positions is skipped without being fetched again. The backfill is complete, and the
   cursor holds none, once the page reaches its low-water mark, the oldest message or the backfill
   depth limit.
   */
  private static func backfillPage(
    account: String,
    limit: Int,
    cursor: inout IMAPSweepCursor,
    from start: Int,
    selection: IMAPMailboxSelection,
    session: IMAPSession
  ) async throws -> [MailEnvelope] {
    guard let backfill = cursor.backfill else { return [] }
    guard start < selection.count else {
      cursor.completeBackfill()
      return []
    }
    let page = try await messages(
      mailbox: "INBOX",
      account: account,
      limit: limit,
      session: session,
      offset: start,
      selection: selection,
      aboveUID: backfill.lowWaterUID,
      belowUID: backfill.ceilingUID
    )
    if (1..<maximumBackfillDepth).contains(page.nextOffset) {
      cursor.offset = page.nextOffset
      if let oldest = page.envelopes.compactMap(\.identity.localID).min() {
        cursor.backfill?.ceilingUID = oldest
      }
    } else {
      cursor.completeBackfill()
    }
    return page.envelopes
  }

  /**
   Reads messages whose UIDs exceed `highWater`, oldest first, within a count and byte budget
   and, after the first fetch, before the session's fetch deadline.

   UIDs grow with arrival order, so the high-water mark advances without gaps. An arrival burst
   deeper than the scan budget leaves its oldest part to the backfill, which ``IMAPArrivals/overflow``
   describes. RFC822.SIZE only
   estimates each message for the budget; a message whose literal exceeds the size limit stays
   unclassified, the mark passes it and reading stops, since the session can't continue.
   */
  static func arrivals(
    account: String,
    limit: Int,
    above highWater: Int,
    selection: IMAPMailboxSelection,
    session: IMAPSession
  ) async throws -> IMAPArrivals {
    let (pending, reached) = try await arrivalMetadata(
      above: highWater,
      selection: selection,
      session: session
    )
    var result = IMAPArrivals(highWater: highWater, scanned: pending.count)
    if !reached, let oldest = pending.last {
      result.overflow = IMAPBackfill(lowWaterUID: highWater, ceilingUID: oldest.uid)
    }
    var bytes = 0
    for row in pending.reversed() {
      guard result.envelopes.count < min(limit, maximumPageSize) * maximumArrivalPages else {
        return result
      }
      if row.size <= MIMEParser.maximumMessageBytes {
        guard row.size <= maximumPageBytes - bytes,
          result.highWater == highWater || !session.isPastFetchDeadline
        else { return result }
        let fetched: Data?
        do {
          fetched = try await fetch(uid: row.uid, session: session)
        } catch IMAPError.limitExceeded {
          result.highWater = row.uid
          return result
        }
        if let raw = fetched {
          guard raw.count <= maximumPageBytes - bytes else { return result }
          bytes += raw.count
          result.envelopes.append(
            envelope(
              raw,
              account: account,
              uid: row.uid,
              mailbox: "INBOX",
              validity: selection.validity
            )
          )
        }
      }
      result.highWater = row.uid
    }
    result.caughtUp = reached
    return result
  }

  private static func arrivalMetadata(
    above highWater: Int,
    selection: IMAPMailboxSelection,
    session: IMAPSession
  ) async throws -> (rows: [IMAPMetadata], reachedHighWater: Bool) {
    var rows: [IMAPMetadata] = [], last = selection.count
    for _ in 0..<maximumArrivalScanPages where last > 0 {
      let first = max(1, last - maximumPageSize + 1)
      let page = try await metadata(range: first...last, limit: maximumPageSize, session: session)
      let newer = page.prefix { $0.uid > highWater }
      rows += newer
      guard newer.count == page.count else { return (rows, true) }
      last = first - 1
    }
    return (rows, last == 0)
  }

  private static func newestUID(_ selection: IMAPMailboxSelection, session: IMAPSession)
    async throws -> Int
  {
    if let uidNext = selection.uidNext { return uidNext - 1 }
    guard !selection.isEmpty else { return 0 }
    let count = selection.count
    guard let newest = try await metadata(range: count...count, limit: 1, session: session).first
    else { throw IMAPError.malformedResponse }
    return newest.uid
  }

  private static func metadata(range: ClosedRange<Int>, limit: Int, session: IMAPSession)
    async throws -> [IMAPMetadata]
  {
    guard let first = UInt32(exactly: range.lowerBound),
      let last = UInt32(exactly: range.upperBound)
    else { throw IMAPError.malformedResponse }
    let reply = try await session.command(
      .fetch(
        .range(
          MessageIdentifierRange(SequenceNumber(rawValue: first)...SequenceNumber(rawValue: last))
        ),
        [.uid, .rfc822Size],
        []
      )
    )
    var result: [IMAPMetadata] = [], seenUIDs: Set<Int> = [], seenSequences: Set<Int> = []
    for fetch in reply.fetches {
      guard let sequence = fetch.sequence, range.contains(sequence) else { continue }
      guard let uid = fetch.uid, uid > 0, uid <= UInt32.max, let size = fetch.size,
        seenUIDs.insert(uid).inserted, seenSequences.insert(sequence).inserted
      else { throw IMAPError.malformedResponse }
      guard result.count < limit else { throw IMAPError.limitExceeded }
      result.append(.init(sequence: sequence, uid: uid, size: size))
    }
    return result.sorted { $0.sequence > $1.sequence }
  }
}

/// New Inbox mail read above a sweep's high-water mark.
struct IMAPArrivals {
  var envelopes: [MailEnvelope] = []
  /// Highest UID read or skipped as unavailable; every newer UID remains unread.
  var highWater: Int
  /// Inbox positions, counted from the newest, that hold UIDs above the previous mark.
  var scanned: Int
  /// Whether every message above the previous mark was read.
  var caughtUp = false
  /// The older part of a burst deeper than the scan budget, which only a backfill reads.
  var overflow: IMAPBackfill?
}

private struct IMAPMetadata {
  var sequence: Int
  var uid: Int
  var size: Int
}
