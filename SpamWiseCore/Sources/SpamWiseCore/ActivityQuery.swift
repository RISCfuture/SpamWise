public import Foundation
import SwiftData

/// Filters the bounded local log without reclassifying messages.
public struct ActivityQuery: Sendable {
  /// Case-insensitive search over sender, subject and reason.
  public var text = ""
  /// Exact account scope; nil includes all accounts.
  public var accountID: String?
  /// Exact decision path; nil includes all paths.
  public var path: DecisionPath?
  /// Exact action outcome; nil includes every outcome.
  public var outcome: ActionOutcome?
  /// Inclusive lower date boundary.
  public var start: Date?
  /// Inclusive upper date boundary.
  public var end: Date?
  /// Restricts to explicit corrections when true.
  public var correctionsOnly = false
  /// The order matching records are listed in; newest first by default.
  public var sort = ActivitySort()
  /// The same filter over stored Activity rows, evaluated by the store.
  var predicate: Predicate<RecordRow> {
    let anyAccount = accountID == nil, account = accountID
    let anyPath = path == nil, path = path?.rawValue ?? ""
    let anyOutcome = outcome == nil, outcome = outcome?.rawValue ?? ""
    let start = start ?? .distantPast, end = end ?? .distantFuture
    let correctionsOnly = correctionsOnly, text = text
    return #Predicate { row in
      (anyAccount || row.accountID == account) && (anyPath || row.path == path)
        && (anyOutcome || row.outcome == outcome) && row.date >= start && row.date <= end
        && (!correctionsOnly || row.correctedLabel != nil)
        && (text.isEmpty || row.sender.localizedStandardContains(text)
          || row.subject.localizedStandardContains(text)
          || row.reason.localizedStandardContains(text))
    }
  }
  /// Creates an unfiltered query.
  public init() {}
  /// Returns matching records in ``sort`` order, retaining original explanations.
  public func apply(to records: [DecisionRecord]) -> [DecisionRecord] {
    records.filter { record in
      (accountID == nil || record.identity.accountID == accountID)
        && (path == nil || record.path == path)
        && (outcome == nil || record.outcome == outcome)
        && (start == nil || record.date >= start!)
        && (end == nil || record.date <= end!)
        && (!correctionsOnly || record.correctedLabel != nil)
        && (text.isEmpty
          || [record.sender, record.subject, record.decision.reason.localizedDescription]
            .contains { $0?.localizedCaseInsensitiveContains(text) == true })
    }.sorted(using: sort.comparators)
  }
}

/// The order Activity lists records in, applied by the store so paging keeps it.
public struct ActivitySort: Sendable, Equatable {
  /// The field records are ordered by; ties fall back to newest first.
  public var key: Key
  /// Whether the order is ascending: oldest, or alphabetical, first.
  public var ascending: Bool

  /// The same order for stored Activity rows.
  var descriptors: [SortDescriptor<RecordRow>] {
    let order: SortOrder = ascending ? .forward : .reverse
    let newestFirst = SortDescriptor(\RecordRow.date, order: .reverse)
    return switch key {
      case .date: [SortDescriptor(\.date, order: order)]
      case .sender: [SortDescriptor(\.sender, order: order), newestFirst]
      case .subject: [SortDescriptor(\.subject, order: order), newestFirst]
    }
  }
  /// The same order for decoded records.
  var comparators: [KeyPathComparator<DecisionRecord>] {
    let order: SortOrder = ascending ? .forward : .reverse
    let newestFirst = KeyPathComparator(\DecisionRecord.date, order: .reverse)
    return switch key {
      case .date: [KeyPathComparator(\.date, order: order)]
      case .sender: [KeyPathComparator(\.sortableSender, order: order), newestFirst]
      case .subject: [KeyPathComparator(\.sortableSubject, order: order), newestFirst]
    }
  }

  /// Creates an order; the default lists the newest decisions first.
  public init(key: Key = .date, ascending: Bool = false) {
    self.key = key
    self.ascending = ascending
  }

  /// A record field Activity can be ordered by.
  public enum Key: Sendable, CaseIterable {
    /// When the decision was made.
    case date
    /// The sender's address.
    case sender
    /// The message subject.
    case subject
  }
}

extension DecisionRecord {
  /// The sender as the store indexes it, empty when unknown.
  fileprivate var sortableSender: String { sender ?? "" }
  /// The subject as the store indexes it, empty when unknown.
  fileprivate var sortableSubject: String { subject ?? "" }
}

/// Operational counts from a bounded log, not a held-out quality measurement.
public struct ActivityStatistics: Codable, Sendable {
  /// The account key for decisions whose account is unknown.
  public static let unknownAccount = "unknown"
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
  /**
   One-sided 95% upper bound on the share of reviewed decisions that disagreed.

   Reviewed decisions are the ones the user chose to correct, so the bound describes that
   sample, not overall accuracy; nil when nothing was reviewed.
   */
  public let reviewedMistakeUpperBound: Double?
  /// Estimated cost recorded on the selected records, including provider connection checks.
  public let estimatedCostUSD: Double
  /// Decisions per account; missing identities remain explicitly unknown.
  public let accountCounts: [String: Int]
  /// Decisions per calendar day, suitable for trends and export.
  public let dailyCounts: [Date: Int]
  /// Decisions per account and calendar day, keyed like ``accountCounts``.
  public let accountDailyCounts: [String: [Date: Int]]
  /**
   Calculates counts without assuming that uncorrected predictions were correct.

   Provider connection checks count toward ``estimatedCostUSD`` but not as decisions.
   */
  public init(records allRecords: [DecisionRecord], calendar: Calendar = .current) {
    estimatedCostUSD = allRecords.reduce(0) { $0 + ($1.verdict?.usage.estimatedCost ?? 0) }
    let records = allRecords.filter { $0.path != .verification }
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
    reviewedMistakeUpperBound = BinomialBound.upper95(
      errors: reviewedMistakes,
      trials: reviewedDecisions
    )
    let byAccount = Dictionary(grouping: records) { $0.identity.accountID ?? Self.unknownAccount }
    accountCounts = byAccount.mapValues(\.count)
    dailyCounts = Self.dailyCounts(of: records, calendar: calendar)
    accountDailyCounts = byAccount.mapValues { Self.dailyCounts(of: $0, calendar: calendar) }
  }

  private static func dailyCounts(of records: [DecisionRecord], calendar: Calendar) -> [Date: Int] {
    Dictionary(grouping: records) { calendar.startOfDay(for: $0.date) }.mapValues(\.count)
  }
}

/// Content-free support snapshot; account identifiers, subjects and sender addresses are omitted.
public struct DiagnosticSummary: Encodable, Sendable {
  /// The reason category of a record whose decision can't be read.
  public static let unreadableReason = "unreadable"
  /// Version of this redacted export format.
  public let version = 1
  /// Whether the user paused filtering.
  public let paused: Bool
  /// Whether mail mutations are suppressed.
  public let dryRun: Bool
  /// Effective incoming route from the current configuration.
  public let route: IncomingRoute
  /// Number of accounts authorized for actions on this installation.
  public let validatedAccountCount: Int
  /// Outcome totals without message or account identity.
  public let outcomes: [String: Int]
  /// Decision reason totals keyed by content-free diagnostic category.
  public let reasons: [String: Int]
  /// Number of pending retries, without retained message content.
  public let retryCount: Int
  /// Exports only fixed-schema operational values, never arbitrary error text.
  init(settings: Settings, retryCount: Int, outcomes: [String: Int], reasons: [String: Int]) {
    paused = settings.paused; dryRun = settings.dryRun
    route = settings.incomingRoute
    validatedAccountCount = settings.validatedAccounts.count
    self.outcomes = outcomes; self.reasons = reasons
    self.retryCount = retryCount
  }
}
