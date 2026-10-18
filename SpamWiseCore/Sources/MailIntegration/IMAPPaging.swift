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
    aboveUID boundary: Int = 0
  ) async throws -> (envelopes: [MailEnvelope], nextOffset: Int) {
    guard limit > 0 else { return ([], offset) }
    let selected: IMAPMailboxSelection
    if let selection {
      selected = selection
    } else {
      selected = try await select(mailbox, writable: false, session: session)
    }
    guard selected.count > 0 else { return ([], 0) }
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
      guard row.size <= IMAPPipeline.maximumBodyBytes else { continue }
      guard row.size <= maximumPageBytes - total else {
        nextOffset = selected.count - row.sequence
        break
      }
      guard let raw = try await fetch(uid: row.uid, session: session) else { continue }
      guard raw.count == row.size else { throw IMAPError.malformedResponse }
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
    var envelopes = arrivals.envelopes
    var offset = cursor.currentOffset(validity: selected.validity, count: selected.count)
    if arrivals.caughtUp, max(offset, arrivals.scanned) < selected.count {
      let backfill = try await messages(
        mailbox: "INBOX",
        account: account,
        limit: limit,
        session: session,
        offset: max(offset, arrivals.scanned),
        selection: selected,
        aboveUID: boundary
      )
      envelopes += backfill.envelopes
      offset = backfill.nextOffset < maximumBackfillDepth ? backfill.nextOffset : 0
    }
    return (
      envelopes,
      IMAPSweepCursor(
        offset: offset,
        validity: selected.validity,
        boundaryUID: boundary,
        highWaterUID: arrivals.highWater
      )
    )
  }

  /**
   Reads messages whose UIDs exceed `highWater`, oldest first, within a count and byte budget.

   UIDs grow with arrival order, so the high-water mark advances without gaps. An arrival burst
   deeper than the scan budget leaves its oldest part to the backfill.
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
    var bytes = 0
    for row in pending.reversed() {
      guard result.envelopes.count < min(limit, maximumPageSize) * maximumArrivalPages else {
        return result
      }
      if row.size <= IMAPPipeline.maximumBodyBytes {
        guard row.size <= maximumPageBytes - bytes else { return result }
        if let raw = try await fetch(uid: row.uid, session: session) {
          guard raw.count == row.size else { throw IMAPError.malformedResponse }
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
    guard selection.count > 0 else { return 0 }
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
}

private struct IMAPMetadata {
  var sequence: Int
  var uid: Int
  var size: Int
}
