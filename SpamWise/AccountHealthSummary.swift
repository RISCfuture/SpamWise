import Foundation
import SpamWiseCore

/// One account's scan health reduced to the single state its summary row shows.
struct AccountHealthSummary: Equatable {
  /// Checks run about once a minute; one that started longer ago than this is reported as late.
  static let lateAfter: TimeInterval = 15 * 60

  /// The most important thing to say about the account's checks.
  let state: State
  /// Messages the latest pass visited, by how they were handled; nil before any pass finished.
  let coverage: SweepCoverage?
  /// Older messages since filtering started that no pass has reached yet.
  let backlog: Int
  /// Unreadable messages the latest pass left in place.
  let unreadable: Int

  /**
   Summarizes `health`, most limiting state first: stalled, failing, late, checked.

   - Parameters:
     - health: The account's recorded scan health, or nil when no check has reached it.
     - now: The time against which a late check is judged.
   */
  init(health: MailScanHealth?, now: Date = .now) {
    coverage = health?.lastSuccess == nil ? nil : health?.coverage
    backlog = health?.unseen ?? 0
    unreadable = health?.unavailableCount ?? 0
    state = Self.state(of: health, now: now)
  }

  private static func state(of health: MailScanHealth?, now: Date) -> State {
    guard let health else { return .notChecked }
    if health.isStalled { return .stalled }
    if let failure = health.failure { return .failing(failure) }
    if case .late(let attempt) = health.heartbeat(now: now, expectedInterval: lateAfter) {
      return .late(lastChecked: health.lastSuccess ?? attempt)
    }
    return health.lastSuccess.map(State.checked) ?? .notChecked
  }

  /// What the account's checks are doing, most limiting first.
  enum State: Equatable {
    /// No check has read the account yet.
    case notChecked
    /// Checks run on schedule; the latest successful read was at this time.
    case checked(Date)
    /// No check has started recently, so SpamWise or Mail may not be running.
    case late(lastChecked: Date)
    /// The latest check failed for this reason.
    case failing(String)
    /// Checks keep timing out on the same page, so smaller pages are being read.
    case stalled
  }
}
