import Foundation
import SpamWiseCore

extension IMAPAdapter {
  static func messages(
    mailbox: String,
    account: String,
    limit: Int,
    session: IMAPSession,
    offset: Int = 0,
    selection: (validity: UInt64, count: Int)? = nil
  ) async throws -> (envelopes: [MailEnvelope], nextOffset: Int) {
    guard limit > 0 else { return ([], offset) }
    let selected: (validity: UInt64, count: Int)
    if let selection {
      selected = selection
    } else {
      selected = try await select(mailbox, writable: false, session: session)
    }
    guard selected.count > 0 else { return ([], 0) }
    let last = max(1, selected.count - offset)
    let first = max(1, last - min(limit, 100) + 1)
    let rows = try await session.command("FETCH \(first):\(last) (UID RFC822.SIZE)")
    let metadata = try metadata(rows, range: first...last, limit: min(limit, 100))
    var envelopes: [MailEnvelope] = []
    var total = 0, nextOffset = selected.count - first + 1
    for row in metadata {
      guard row.size <= 2_000_000 else { continue }
      guard row.size <= 4_000_000 - total else {
        nextOffset = selected.count - row.sequence
        break
      }
      guard let raw = try await fetch(uid: row.uid, session: session) else { continue }
      guard raw.count == row.size else { throw IMAPError.malformedResponse }
      total += raw.count
      let identity = MessageIdentity(
        accountID: account,
        messageID: (try? MIMEParser().parse(raw))?.header("message-id"),
        localID: row.uid,
        mailboxValidity: selected.validity,
        mailbox: mailbox,
        contentHash: stableHash(raw)
      )
      envelopes.append(.init(identity: identity, raw: raw))
    }
    return (envelopes, nextOffset >= selected.count ? 0 : nextOffset)
  }

  private static func metadata(_ rows: [[IMAPToken]], range: ClosedRange<Int>, limit: Int) throws
    -> [IMAPMetadata]
  {
    var result: [IMAPMetadata] = [], seenUIDs: Set<Int> = [], seenSequences: Set<Int> = []
    for row in rows where isFetch(row) {
      guard let sequence = row[1].text.flatMap(Int.init), range.contains(sequence) else { continue }
      guard let uid = number("UID", in: row), uid > 0, uid <= UInt32.max,
        let size = number("RFC822.SIZE", in: row), seenUIDs.insert(uid).inserted,
        seenSequences.insert(sequence).inserted
      else { throw IMAPError.malformedResponse }
      guard result.count < limit else { throw IMAPError.limitExceeded }
      result.append(.init(sequence: sequence, uid: uid, size: size))
    }
    return result.sorted { $0.sequence > $1.sequence }
  }
}

private struct IMAPMetadata {
  var sequence: Int
  var uid: Int
  var size: Int
}
