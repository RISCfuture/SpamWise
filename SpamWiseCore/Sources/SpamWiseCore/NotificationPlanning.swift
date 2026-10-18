public import Foundation

/// Opt-in local notification policy; content is summarized without subjects or senders.
public struct NotificationPreferences: Codable, Sendable, Equatable {
  /// Allowed spacing between notification batches, in minutes.
  public static let intervalRangeMin = 5...1440
  /// Explicit activation time; earlier Activity is never announced retroactively.
  public var enabledSince: Date?
  /// Whether confirmed Inbox decisions are included alongside unresolved Review.
  public var includeGood = false
  /// Minimum spacing between notification batches, clamped to ``intervalRangeMin``.
  public var intervalMin = 30
  /// Local-clock quiet period start; equal endpoints disable quiet hours.
  public var quietStartHour = 22
  /// Local-clock quiet period end, supporting overnight periods.
  public var quietEndHour = 8
  /// ``intervalMin`` limited to ``intervalRangeMin``.
  var boundedIntervalMin: Int {
    min(Self.intervalRangeMin.upperBound, max(Self.intervalRangeMin.lowerBound, intervalMin))
  }
  /// Creates disabled, quiet notification defaults.
  public init() {}
  /**
   Whether `date` falls in the quiet period, which may run overnight.

   Equal start and end hours disable quiet hours; an hour outside 0 through 23 makes every time
   quiet.
   */
  public func isQuiet(at date: Date, calendar: Calendar = .current) -> Bool {
    guard (0...23).contains(quietStartHour), (0...23).contains(quietEndHour) else { return true }
    guard quietStartHour != quietEndHour else { return false }
    let hour = calendar.component(.hour, from: date)
    return quietStartHour < quietEndHour
      ? (quietStartHour..<quietEndHour).contains(hour)
      : hour >= quietStartHour || hour < quietEndHour
  }
}

/// Counts only, suitable for a notification that discloses no mail content.
public struct NotificationBatch: Sendable {
  /// Number of unique unresolved Review messages.
  public let review: Int
  /// Number of newly recognized Inbox messages, when opted in.
  public let good: Int
}

/// Durable at-most-once announcement claims, independent of action and decision outcomes.
public enum NotificationPlanning {
  private static let key = "notification-ledger-v1"
  /**
   Claims eligible records before delivery; failed notification requests do not replay on restart.

   Activity since activation is read only once the batch interval has elapsed. Claims are kept
   only for messages still in the bounded Activity log, so the ledger stays within its bound.
   */
  public static func claim(store: Store, now: Date = .now, calendar: Calendar = .current)
    async throws -> NotificationBatch?
  {
    let settings = try await StateRepository.load(store, StateSlices()).settings
    let preferences = settings.mailOptions.notifications
    guard let since = preferences.enabledSince, !settings.paused,
      !settings.dryRun, !preferences.isQuiet(at: now, calendar: calendar)
    else { return nil }
    let intervalSec = Double(preferences.boundedIntervalMin) * 60
    let lastBatch = try await store.read(key, default: Ledger()).lastBatch
    guard now.timeIntervalSince(lastBatch ?? since) >= intervalSec else { return nil }
    var query = ActivityQuery(); query.start = since
    let records = try await StateRepository.activity(
      store,
      matching: query,
      limit: RetentionLimits.activityRecords
    )
    let latest = Dictionary(grouping: records, by: { $0.identity.key }).values.compactMap {
      $0.max { $0.date < $1.date }
    }
    let eligible = latest.filter {
      $0.date >= since && $0.date <= now && $0.correctedLabel == nil && $0.path != .verification
        && [.applied, .noAction, .failed, .requested].contains($0.outcome)
        && ($0.decision.label == .review
          || (preferences.includeGood && $0.decision.label == .inbox))
    }
    return try await store.update(key, default: Ledger()) { ledger in
      guard now.timeIntervalSince(ledger.lastBatch ?? since) >= intervalSec else { return nil }
      ledger.claims.formIntersection(Set(records.map { $0.identity.key }))
      let pending = eligible.filter { !ledger.claims.contains($0.identity.key) }
      guard !pending.isEmpty else { return nil }
      ledger.claims.formUnion(pending.map { $0.identity.key })
      ledger.lastBatch = now
      return NotificationBatch(
        review: pending.filter { $0.decision.label == .review }.count,
        good: pending.filter { $0.decision.label == .inbox }.count
      )
    }
  }
  private struct Ledger: Codable, Sendable {
    var lastBatch: Date?
    var claims: Set<String> = []
  }
}
