public import Foundation
import SwiftData

/// Explicit privacy and account scope for Mail.app workflows.
public struct MailPreferences: Codable, Sendable, Equatable {
  /// Preferences for unreadable stored values: local-only processing of no accounts.
  static var restrictive: Self {
    var preferences = Self()
    preferences.localOnly = true
    preferences.accountIDs = []
    return preferences
  }
  /// Suppresses all external evidence and requires an on-device classifier.
  public var localOnly = false
  /// Included Mail account identifiers; nil includes all configured accounts.
  public var accountIDs: Set<String>?
  /// Addresses excluded from implicit Contacts and correspondence trust.
  public var trustExclusions: Set<String> = []
  /// Excludes discovered own addresses from implicit relationship trust.
  public var excludeOwnAddresses = true
  /**
   Lowercased receiving-server authserv-ids whose topmost Authentication-Results headers each
   account trusts, by account identifier.

   An account without an entry trusts no authentication result, so its sender relationships and
   Allow rules reach the classifier as evidence instead of deciding messages.
   */
  public var trustedAuthServers: [String: Set<String>] = [:]
  /// Explicitly configured non-Inbox filtering and dedicated-training folders.
  public var folderPlans: [MailFolderPlan] = []
  /// Opt-in read-status follow-up after a confirmed Junk move.
  public var markJunkRead = false
  /// Local notification policy, disabled until the user grants permission and enables it.
  public var notifications = NotificationPreferences()
  /// Creates defaults that include every account, trust no receiving server and enable no folder plans.
  public init() {}
  /**
   Decodes each field independently, using its default when absent.

   An unreadable field also takes its default, except that local-only processing and the account
   selection take their restrictive values: local only, and no accounts.
   */
  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    let defaults = Self(), restrictive = Self.restrictive
    localOnly = values.lenient(
      .localOnly,
      default: defaults.localOnly,
      unreadable: restrictive.localOnly
    )
    accountIDs = values.lenient(
      .accountIDs,
      default: defaults.accountIDs,
      unreadable: restrictive.accountIDs
    )
    trustExclusions = values.lenient(.trustExclusions, default: defaults.trustExclusions)
    excludeOwnAddresses = values.lenient(
      .excludeOwnAddresses,
      default: defaults.excludeOwnAddresses
    )
    trustedAuthServers = values.lenient(.trustedAuthServers, default: defaults.trustedAuthServers)
    folderPlans = values.lenient(.folderPlans, default: defaults.folderPlans)
    markJunkRead = values.lenient(.markJunkRead, default: defaults.markJunkRead)
    notifications = values.lenient(.notifications, default: defaults.notifications)
  }
  private enum CodingKeys: String, CodingKey {
    case localOnly, accountIDs, trustExclusions, excludeOwnAddresses, folderPlans, markJunkRead
    case notifications, trustedAuthServers
  }
}

/// Durable progress for one account's repeating Inbox sweep.
public struct MailScanHealth: Codable, Sendable, Equatable {
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
  public var unavailableInSweep = 0
  /// Unreadable entries in the most recently completed traversal.
  public var lastSweepUnavailable = 0
  /// Most recent traversal's unreadable count, without claiming full coverage.
  public var unavailableCount: Int { nextOffset == 0 ? lastSweepUnavailable : unavailableInSweep }
  /// Latest attempted page read.
  public var lastAttempt: Date?
  /// Latest page whose readable envelopes were handled and unreadable count recorded.
  public var lastSuccess: Date?
  /// Latest completed sweep; mailbox mutations may require another sweep.
  public var lastCompletedSweep: Date?
  /// Sanitized integration failure, cleared by the next successful page.
  public var failure: String?
  /// A condition of the latest traversal that limits what it did without being a failure.
  public var note: String?
  /// Passes in a row that failed, cleared by the next successful page.
  public var consecutiveFailures = 0
  /// Passes in a row whose page read timed out, cleared by a pass without a timeout.
  public var consecutiveTimeouts = 0
  /// How the messages visited by the latest pass were handled.
  public var coverage = SweepCoverage()
  /// Creates a progress record without claiming any mail was read.
  public init(accountName: String) { self.accountName = accountName }
  /// Decodes each field independently, using its default when absent or unreadable.
  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    self.init(accountName: values.lenient(.accountName, default: ""))
    inboxStart = values.lenient(.inboxStart, default: nil)
    nextOffset = values.lenient(.nextOffset, default: 0)
    observedTotal = values.lenient(.observedTotal, default: 0)
    scanned = values.lenient(.scanned, default: 0)
    unavailableInSweep = values.lenient(.unavailableInSweep, default: 0)
    lastSweepUnavailable = values.lenient(.lastSweepUnavailable, default: 0)
    lastAttempt = values.lenient(.lastAttempt, default: nil)
    lastSuccess = values.lenient(.lastSuccess, default: nil)
    lastCompletedSweep = values.lenient(.lastCompletedSweep, default: nil)
    failure = values.lenient(.failure, default: nil)
    note = values.lenient(.note, default: nil)
    consecutiveFailures = values.lenient(.consecutiveFailures, default: 0)
    consecutiveTimeouts = values.lenient(.consecutiveTimeouts, default: 0)
    coverage = values.lenient(.coverage, default: SweepCoverage())
  }
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
    unavailableInSweep += max(0, unavailable)
    scanned += max(0, visited)
    nextOffset = max(0, end)
    lastSuccess = now
    failure = nil
    consecutiveFailures = 0
    guard nextOffset == 0 else { return }
    scanned = 0
    lastSweepUnavailable = unavailableInSweep
    unavailableInSweep = 0
    lastCompletedSweep = now
  }
  private enum CodingKeys: String, CodingKey {
    case accountName, inboxStart, nextOffset, observedTotal, scanned, unavailableInSweep
    case lastSweepUnavailable, lastAttempt, lastSuccess, lastCompletedSweep, failure, note
    case consecutiveFailures, consecutiveTimeouts, coverage
  }
}

/// Account-scoped progress retained separately from the bounded Activity log.
public enum MailHealthRepository {
  static let slice = "mailHealth"
  /// Loads progress without relying on cross-process notifications.
  public static func load(_ store: Store) async throws -> [String: MailScanHealth] {
    try await StatePersistence.prepared(store)
    return try await store.transaction { context in
      try context.fetch(FetchDescriptor<MailHealthRow>()).reduce(into: [:]) { states, row in
        states[row.key] = try? JSONDecoder().decode(MailScanHealth.self, from: row.payload)
      }
    }
  }
  /// Loads one account's or folder's progress.
  public static func load(_ store: Store, key: String) async throws -> MailScanHealth? {
    try await StatePersistence.prepared(store)
    return try await store.transaction { context in
      try context.fetch(FetchDescriptor(predicate: MailHealthRow.keyed([key]))).first.flatMap {
        try? JSONDecoder().decode(MailScanHealth.self, from: $0.payload)
      }
    }
  }
  /// Updates one account without replacing concurrent progress for another.
  public static func update(
    _ store: Store,
    accountID: String,
    name: String,
    _ edit: @Sendable (inout MailScanHealth) -> Void
  ) async throws {
    try await StatePersistence.prepared(store)
    try await store.transaction { context in
      let row = try context.fetch(FetchDescriptor(predicate: MailHealthRow.keyed([accountID])))
        .first
      var health =
        row.flatMap { try? JSONDecoder().decode(MailScanHealth.self, from: $0.payload) }
        ?? MailScanHealth(accountName: name)
      health.accountName = name
      edit(&health)
      let payload = try JSONEncoder().encode(health)
      if let row {
        row.payload = payload
      } else {
        context.insert(MailHealthRow(key: accountID, payload: payload))
      }
      try context.markChanged([slice], stamp: context.nextChangeStamp())
      try context.save()
    }
  }
}
