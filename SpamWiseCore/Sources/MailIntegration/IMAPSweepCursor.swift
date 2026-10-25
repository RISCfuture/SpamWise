public import SpamWiseCore

/// Inbox mail read by ``IMAPAdapter/nextInboxSweep(limit:cursorStore:)``, awaiting its commit.
public struct IMAPInboxSweep: Sendable {
  /// New mail, oldest first, followed by any backfill page.
  public let messages: [MailEnvelope]
  let cursor: IMAPSweepCursor
}

struct IMAPSweepCursor: Codable, Sendable {
  /// Position, counted from the newest message, where the pending backfill resumes.
  var offset = 0
  var validity: UInt64?
  /// Highest UID that existed when this UIDVALIDITY was first swept; older mail is never read.
  var boundaryUID: Int?
  /// Highest UID new-mail reads have reached; newer UIDs are read before the backfill.
  var highWaterUID: Int?
  /// Mail an arrival burst too deep to scan left unread; nil once the backfill is complete.
  var backfill: IMAPBackfill?

  func currentOffset(validity: UInt64, count: Int) -> Int {
    self.validity == validity && offset >= 0 && offset < count ? offset : 0
  }

  func boundary(validity: UInt64) -> Int? {
    self.validity == validity ? boundaryUID : nil
  }

  mutating func completeBackfill() {
    offset = 0; backfill = nil
  }
}

/**
 The unread UIDs between a low-water mark and a ceiling, which the backfill reads newest first.

 Every UID at or above the ceiling and every UID at or below the low-water mark was already
 read, so the backfill skips the former without fetching them and ends at the latter.
 */
struct IMAPBackfill: Codable, Sendable, Equatable {
  /// Highest UID read before the burst; the backfill is complete once it reaches this UID.
  var lowWaterUID: Int
  /// Oldest UID read so far during or after the burst.
  var ceilingUID: Int

  /// The range covering both this backfill and `other`.
  func merged(with other: Self) -> Self {
    Self(
      lowWaterUID: min(lowWaterUID, other.lowWaterUID),
      ceilingUID: max(ceilingUID, other.ceilingUID)
    )
  }
}
