public import Foundation

/// Filters the bounded local log without reclassifying messages.
public struct ActivityQuery: Sendable {
  /// Case-insensitive sender, subject, reason or account search.
  public var text = ""
  /// Exact account scope; nil includes all accounts.
  public var accountID: String?
  /// Exact decision path; nil includes all paths.
  public var path: String?
  /// Exact action outcome; nil includes every outcome.
  public var outcome: ActionOutcome?
  /// Inclusive lower date boundary.
  public var start: Date?
  /// Inclusive upper date boundary.
  public var end: Date?
  /// Restricts to explicit corrections when true.
  public var correctionsOnly = false
  /// Creates an unfiltered query.
  public init() {}
  /// Returns matching records newest first, retaining original explanations.
  public func apply(to records: [DecisionRecord]) -> [DecisionRecord] {
    records.filter { record in
      (accountID == nil || record.identity.accountID == accountID)
        && (path == nil || record.path == path)
        && (outcome == nil || record.outcome == outcome)
        && (start == nil || record.date >= start!)
        && (end == nil || record.date <= end!)
        && (!correctionsOnly || record.correctedLabel != nil)
        && (text.isEmpty
          || [
            record.sender, record.subject, record.decision.reason,
            record.identity.accountID ?? ""
          ].contains { $0.localizedCaseInsensitiveContains(text) })
    }.sorted { $0.date > $1.date }
  }
}

/// Operational counts from a bounded log, not a held-out quality measurement.
public struct ActivityStatistics: Codable, Sendable {
  /// Number of retained decision records, including corrections and retries.
  public let decisions: Int
  /// Latest unique messages still requiring review.
  public let unresolvedReview: Int
  /// Recorded action failures.
  public let actionFailures: Int
  /// Model or gate decisions with an explicit subsequent correction.
  public let reviewedDecisions: Int
  /// Reviewed decisions that disagreed with their correction.
  public let reviewedMistakes: Int
  /// Estimated cost recorded on the selected decisions.
  public let estimatedCostUSD: Double
  /// Decisions per account; missing identities remain explicitly unknown.
  public let accountCounts: [String: Int]
  /// Decisions per calendar day, suitable for trends and export.
  public let dailyCounts: [Date: Int]
  /// Calculates counts without assuming that uncorrected predictions were correct.
  public init(records: [DecisionRecord], calendar: Calendar = .current) {
    decisions = records.count
    let latest = Dictionary(grouping: records, by: { $0.identity.key }).values.compactMap {
      $0.max { $0.date < $1.date }
    }
    unresolvedReview =
      latest.filter { $0.decision.label == .review && $0.correctedLabel == nil }.count
    actionFailures = records.filter { $0.outcome == .failed }.count
    let reviewed = records.filter { $0.verdict != nil && $0.correctedLabel != nil }
    reviewedDecisions = reviewed.count
    reviewedMistakes = reviewed.filter { $0.decision.label != $0.correctedLabel }.count
    estimatedCostUSD = records.reduce(0) { $0 + ($1.verdict?.usage.estimatedCost ?? 0) }
    accountCounts = Dictionary(grouping: records, by: { $0.identity.accountID ?? "unknown" })
      .mapValues(\.count)
    dailyCounts = Dictionary(grouping: records, by: { calendar.startOfDay(for: $0.date) })
      .mapValues(\.count)
  }
}

/// Content-free support snapshot; account identifiers, subjects and sender addresses are omitted.
public struct DiagnosticSummary: Encodable, Sendable {
  /// Version of this redacted export format.
  public let version = 1
  /// Whether the user paused filtering.
  public let paused: Bool
  /// Whether mail mutations are suppressed.
  public let dryRun: Bool
  /// Configured incoming route, independent of runtime validation.
  public let route: IncomingRoute
  /// Number of accounts authorized for actions on this installation.
  public let validatedAccountCount: Int
  /// Outcome totals without message or account identity.
  public let outcomes: [String: Int]
  /// Number of pending retries, without retained message content.
  public let retryCount: Int
  /// Exports only fixed-schema operational values, never arbitrary error text.
  public init(state: AppState) {
    paused = state.settings.paused; dryRun = state.settings.dryRun
    route = state.settings.route; validatedAccountCount = state.settings.validatedAccounts.count
    outcomes = Dictionary(grouping: state.records, by: { $0.outcome.rawValue }).mapValues(\.count)
    retryCount = state.retries.count
  }
}
