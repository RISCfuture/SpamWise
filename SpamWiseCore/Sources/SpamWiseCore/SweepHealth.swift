public import Foundation

/// How the messages one sweep pass visited were handled.
public struct SweepCoverage: Codable, Sendable, Equatable {
  /// Messages classified as Inbox or Junk mail.
  public var classified = 0
  /// Messages classified as needing the user's review.
  public var reviewed = 0
  /// Messages with no classification: unreadable, failed, deferred or left by a pause.
  public var unclassified = 0
  /// Every message the pass visited.
  public var visited: Int { classified + reviewed + unclassified }
  /// Creates empty coverage.
  public init() {}
  /// Decodes each count independently, using zero when absent or unreadable.
  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    classified = values.lenient(.classified, default: 0)
    reviewed = values.lenient(.reviewed, default: 0)
    unclassified = values.lenient(.unclassified, default: 0)
  }
  /// Counts one message by its processed-message result; a missing result counts as unclassified.
  public mutating func count(_ result: ProcessedMessage?) {
    switch result?.isClassified == true ? result?.label : nil {
      case .review: reviewed += 1
      case .inbox, .junk: classified += 1
      case nil: unclassified += 1
    }
  }
  private enum CodingKeys: String, CodingKey { case classified, reviewed, unclassified }
}

/// How recently the sweeper reached an account compared with its schedule.
public enum SweepHeartbeat: Sendable, Equatable {
  /// No pass has started.
  case never
  /// The latest pass started within the expected interval.
  case current(Date)
  /// The latest pass started longer ago than the expected interval.
  case late(Date)
}

extension MailScanHealth {
  /// Consecutive timeouts after which the page size reaches one message.
  public static let shrinkingTimeouts = 4
  /// Consecutive timeouts after which a backfill position that still times out is skipped.
  public static let skippingTimeouts = 6

  /// Positions between the backfill cursor and the end of the observed mailbox not yet visited.
  public var unseen: Int { nextOffset == 0 ? 0 : max(0, observedTotal - nextOffset) }
  /// Whether recent passes keep timing out on the same page.
  public var isStalled: Bool { consecutiveTimeouts >= Self.shrinkingTimeouts }

  /// The page size for the next pass: halved after each consecutive timeout, never below one.
  public func pageLimit(for limit: Int) -> Int {
    max(1, limit >> min(consecutiveTimeouts, Int.bitWidth - 2))
  }

  /// Whether the latest pass started within `interval` of `now`.
  public func heartbeat(now: Date = .now, expectedInterval interval: TimeInterval) -> SweepHeartbeat
  {
    guard let lastAttempt else { return .never }
    return now.timeIntervalSince(lastAttempt) <= interval
      ? .current(lastAttempt) : .late(lastAttempt)
  }

  /// Records a pass that reached its end without a page timeout.
  public mutating func completePass(_ traversal: InboxTraversal, coverage: SweepCoverage) {
    consecutiveTimeouts = 0
    self.coverage = coverage
    complete(
      through: traversal.end,
      visited: traversal.visited,
      total: traversal.total,
      unavailable: traversal.unavailable
    )
  }

  /**
   Records a pass that ended on a page timeout.

   Pages before the timeout keep their progress. Once timeouts persist at a one-message page in
   the backfill, the stalled position is counted as unreadable and skipped, so later mail is
   still reached; a stalled newest page is never skipped.
   */
  public mutating func recordStall(
    _ traversal: InboxTraversal,
    coverage: SweepCoverage,
    failure description: String
  ) {
    if traversal.visited > 0 {
      self.coverage = coverage
      complete(
        through: traversal.end,
        visited: traversal.visited,
        total: traversal.total,
        unavailable: traversal.unavailable
      )
    }
    consecutiveTimeouts += 1
    failure = description
    if let offset = traversal.stalledOffset, offset > 0,
      consecutiveTimeouts >= Self.skippingTimeouts
    {
      consecutiveTimeouts = 0
      complete(
        through: offset + 1,
        visited: 1,
        total: max(observedTotal, offset + 1),
        unavailable: 1
      )
    }
  }

  /// Records a failed pass without moving its cursor.
  public mutating func recordFailure(_ description: String) {
    failure = description
    consecutiveFailures += 1
  }
}
