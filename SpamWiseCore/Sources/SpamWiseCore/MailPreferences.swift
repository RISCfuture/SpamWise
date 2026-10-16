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
  /// Creates conservative defaults without changing existing account scope.
  public init() {}
}

/// Durable progress for one account's repeating Inbox sweep.
public struct MailScanHealth: Codable, Sendable {
  /// Account display name, independent of its persistent identifier.
  public var accountName: String
  /// Offset of the next page, advanced only after processing the current page.
  public var nextOffset = 0
  /// Number of messages reported by Mail during the latest page read.
  public var observedTotal = 0
  /// Number of envelopes processed during the current sweep.
  public var scanned = 0
  /// Latest attempted page read.
  public var lastAttempt: Date?
  /// Latest fully processed page.
  public var lastSuccess: Date?
  /// Latest completed sweep; mailbox mutations may require another sweep.
  public var lastCompletedSweep: Date?
  /// Sanitized integration failure, cleared by the next successful page.
  public var failure: String?
  /// Creates a progress record without claiming any mail was read.
  public init(accountName: String) { self.accountName = accountName }
  /// Records progress only after every envelope in the page has been handled.
  public mutating func complete(count: Int, total: Int, now: Date = .now) {
    observedTotal = max(0, total)
    scanned += max(0, count)
    nextOffset += max(0, count)
    lastSuccess = now
    failure = nil
    if count == 0 || nextOffset >= observedTotal {
      nextOffset = 0
      scanned = 0
      lastCompletedSweep = now
    }
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
