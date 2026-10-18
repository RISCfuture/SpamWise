public import Foundation

/// Explicit privacy and account scope for Mail.app workflows.
public struct MailPreferences: Codable, Sendable, Equatable {
  /// Suppresses all external evidence and requires an on-device classifier.
  public var localOnly = false
  /// Included Mail account identifiers; nil includes all configured accounts.
  public var accountIDs: Set<String>?
  /// Addresses excluded from implicit Contacts and correspondence trust.
  public var trustExclusions: Set<String> = []
  /// Excludes discovered own addresses from implicit relationship trust.
  public var excludeOwnAddresses = true
  /// Optional explicitly configured non-Inbox filtering and dedicated-training folders.
  public var folderPlans: [MailFolderPlan]?
  /// Opt-in read-status follow-up after a confirmed Junk move; nil means disabled.
  public var markJunkRead: Bool?
  /// Optional local notification policy, disabled until the user grants permission and enables it.
  public var notifications: NotificationPreferences?
  /// Creates conservative defaults without changing existing account scope.
  public init() {}
}

/// Durable progress for one account's repeating Inbox sweep.
public struct MailScanHealth: Codable, Sendable {
  /// Account display name, independent of its persistent identifier.
  public var accountName: String
  /// Earliest received date automatic Inbox filtering considers for this account.
  public var inboxStart: Date?
  /// Offset of the next backfill page, advanced only after processing the current page.
  public var nextOffset = 0
  /// Number of Inbox messages received since `inboxStart`, as Mail reported during the latest read.
  public var observedTotal = 0
  /// Number of mailbox positions visited during the current sweep.
  public var scanned = 0
  /// Unreadable entries observed in the current sweep.
  public var unavailableInSweep: Int?
  /// Unreadable entries in the most recently completed traversal.
  public var lastSweepUnavailable: Int?
  /// Most recent traversal's unreadable count, without claiming full coverage.
  public var unavailableCount: Int {
    (nextOffset == 0 ? lastSweepUnavailable : unavailableInSweep) ?? 0
  }
  /// Latest attempted page read.
  public var lastAttempt: Date?
  /// Latest page whose readable envelopes were handled and unreadable count recorded.
  public var lastSuccess: Date?
  /// Latest completed sweep; mailbox mutations may require another sweep.
  public var lastCompletedSweep: Date?
  /// Sanitized integration failure, cleared by the next successful page.
  public var failure: String?
  /// Creates a progress record without claiming any mail was read.
  public init(accountName: String) { self.accountName = accountName }
  /// Records visited positions after handling readable envelopes and counting unavailable entries.
  public mutating func complete(count: Int, total: Int, unavailable: Int = 0, now: Date = .now) {
    let end = nextOffset + max(0, count)
    complete(
      through: count == 0 || end >= total ? 0 : end,
      visited: count,
      total: total,
      unavailable: unavailable,
      now: now
    )
  }
  /// Records visited positions and moves the next page to `end`; zero completes the traversal.
  public mutating func complete(
    through end: Int,
    visited: Int,
    total: Int,
    unavailable: Int = 0,
    now: Date = .now
  ) {
    observedTotal = max(0, total)
    unavailableInSweep = (unavailableInSweep ?? 0) + max(0, unavailable)
    scanned += max(0, visited)
    nextOffset = max(0, end)
    lastSuccess = now
    failure = nil
    guard nextOffset == 0 else { return }
    scanned = 0
    lastSweepUnavailable = unavailableInSweep
    unavailableInSweep = 0
    lastCompletedSweep = now
  }
}

/// Account-scoped progress retained separately from the bounded Activity log.
public enum MailHealthRepository {
  private static let key = "mail-health-v1"
  /// Loads progress without relying on cross-process notifications.
  public static func load(_ store: Store) async throws -> [String: MailScanHealth] {
    try await store.read(key, default: [:])
  }
  /// Updates one account without replacing concurrent progress for another.
  public static func update(
    _ store: Store,
    accountID: String,
    name: String,
    _ edit: @Sendable (inout MailScanHealth) -> Void
  ) async throws {
    try await store.update(key, default: [String: MailScanHealth]()) { states in
      var health = states[accountID] ?? MailScanHealth(accountName: name)
      health.accountName = name
      edit(&health)
      states[accountID] = health
    }
  }
}
