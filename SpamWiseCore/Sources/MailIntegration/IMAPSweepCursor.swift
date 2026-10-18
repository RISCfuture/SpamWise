public import SpamWiseCore

/// Inbox mail read by ``IMAPAdapter/nextInboxSweep(limit:cursorStore:)``, awaiting its commit.
public struct IMAPInboxSweep: Sendable {
  /// New mail, oldest first, followed by any backfill page.
  public let messages: [MailEnvelope]
  let cursor: IMAPSweepCursor
}

struct IMAPSweepCursor: Codable, Sendable {
  var offset = 0
  var validity: UInt64?
  /// Highest UID that existed when this UIDVALIDITY was first swept; older mail is never read.
  var boundaryUID: Int?
  /// Highest UID new-mail reads have reached; newer UIDs are read before the backfill.
  var highWaterUID: Int?

  func currentOffset(validity: UInt64, count: Int) -> Int {
    self.validity == validity && offset >= 0 && offset < count ? offset : 0
  }

  func boundary(validity: UInt64) -> Int? {
    self.validity == validity ? boundaryUID : nil
  }
}
