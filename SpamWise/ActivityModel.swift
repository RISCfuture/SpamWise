import Foundation
import Observation
import SpamWiseCore

/**
 The Activity log as the table shows it: the newest matching records, fetched page by page from
 the store's indexed rows instead of filtering the whole log in memory.

 Without a store, as in previews, the model filters the fixture records it was given.
 */
@MainActor
@Observable
final class ActivityModel {
  /// Records added to the table each time the user asks for more.
  static let pageSize = 200
  private static let searchDelay: Duration = .milliseconds(250)
  /// The table's filter; changing it starts over at the first page.
  var query = ActivityQuery() {
    didSet {
      visibleLimit = Self.pageSize
      queryRevision += 1
    }
  }
  /// The newest records matching ``query``, up to the number shown.
  private(set) var rows: [DecisionRecord] = []
  /// Every record matching ``query``.
  private(set) var matchingCount = 0
  /// Today's decisions, whatever the filter.
  private(set) var today = TodaySummary()
  /// Why the latest reload failed, until one succeeds.
  private(set) var loadFailure: OperationFailure?
  /// How many matching records the table shows.
  private(set) var visibleLimit = ActivityModel.pageSize
  /// Changes whenever ``query`` does.
  private(set) var queryRevision = 0
  @ObservationIgnored private let store: Store?
  @ObservationIgnored private let shared: SharedStateModel

  var canShowMore: Bool { rows.count < matchingCount }
  /// The table's sort order, kept in ``query`` so the store applies it to every page.
  var sortOrder: [KeyPathComparator<DecisionRecord>] {
    get { [ActivitySortColumn.comparator(for: query.sort)] }
    set { query.sort = newValue.first.map(ActivitySortColumn.sort(for:)) ?? ActivitySort() }
  }
  /// Whether only today's decisions are shown.
  var showsTodayOnly: Bool {
    get { query.start == TodaySummary.query.start && query.end == nil }
    set {
      query.start = newValue ? TodaySummary.query.start : nil
      query.end = nil
    }
  }

  init(store: Store, shared: SharedStateModel) {
    self.store = store
    self.shared = shared
  }

  /// A model over fixed records, for previews.
  init(fixtures: [DecisionRecord], shared: SharedStateModel) {
    store = nil
    self.shared = shared
    rows = ActivityQuery().apply(to: fixtures)
    matchingCount = rows.count
    today = TodaySummary(TodaySummary.query.apply(to: rows))
  }

  /// Shows another page of matching records.
  func showMore() { visibleLimit += Self.pageSize }

  /// Removes every filter, keeping the search text and sort order.
  func clearFilters() {
    var cleared = ActivityQuery()
    cleared.text = query.text
    cleared.sort = query.sort
    query = cleared
  }

  /// The shown record with `id`.
  func record(id: UUID?) -> DecisionRecord? {
    rows.first { $0.id == id }
  }

  /// Fetches the shown page and today's counts, after a short pause so typing coalesces.
  func reload() async {
    guard let store else { return }
    do {
      try await Task.sleep(for: Self.searchDelay)
      let query = query, limit = visibleLimit
      let page = try await StateRepository.activity(store, matching: query, limit: limit)
      let count = try await StateRepository.activityCount(store, matching: query)
      let today = TodaySummary(try await records(matching: TodaySummary.query))
      try Task.checkCancellation()
      rows = page
      matchingCount = count
      self.today = today
      loadFailure = nil
    } catch is CancellationError {
    } catch {
      loadFailure = OperationFailure(error)
    }
  }

  /// Every retained record matching `query`, newest first.
  func records(matching query: ActivityQuery) async throws -> [DecisionRecord] {
    guard let store else { return query.apply(to: rows) }
    return try await StateRepository.activity(
      store,
      matching: query,
      limit: RetentionLimits.activityRecords
    )
  }

  /// This week's Review digest.
  func digest() async throws -> ReviewDigest {
    guard let store else {
      var state = AppState()
      state.records = rows
      return ReviewDigest(state: state)
    }
    return try await ReviewDigest.load(from: store)
  }

  /// The redacted diagnostics that the status intent also returns.
  func diagnostics() async throws -> Data {
    guard let store else { throw SharedStorageError.unavailable }
    let state = try await StateRepository.load(store, StateSlices(records: .all, retries: .all))
    return try JSONEncoder.pretty.encode(DiagnosticSummary(state: state))
  }

  /// Distinct senders seen in Activity or corrections at each of `domains`.
  func knownSenderCounts(atDomains domains: Set<String>) async -> [String: Int] {
    var state = AppState()
    state.corrections = shared.state.corrections
    for domain in domains {
      var query = ActivityQuery()
      query.text = domain
      state.records += (try? await records(matching: query)) ?? []
    }
    return state.knownSenderCounts(atDomains: domains)
  }
}

extension ActivityQuery {
  /// Whether a filter other than the search text hides some records.
  var hasFilters: Bool {
    accountID != nil || path != nil || outcome != nil || start != nil || end != nil
      || correctionsOnly
  }
}

/// The Activity table's sortable columns and the store order each one requests.
enum ActivitySortColumn {
  /// The store order a column's comparator requests; an unknown column falls back to newest first.
  static func sort(for comparator: KeyPathComparator<DecisionRecord>) -> ActivitySort {
    guard
      let key = ActivitySort.Key.allCases.first(where: { keyPath(for: $0) == comparator.keyPath })
    else { return ActivitySort() }
    return ActivitySort(key: key, ascending: comparator.order == .forward)
  }

  private static func keyPath(for key: ActivitySort.Key) -> PartialKeyPath<DecisionRecord> {
    switch key {
      case .date: \DecisionRecord.date
      case .sender: \DecisionRecord.displaySender
      case .subject: \DecisionRecord.displaySubject
    }
  }

  /// The comparator the table shows for a store order.
  static func comparator(for sort: ActivitySort) -> KeyPathComparator<DecisionRecord> {
    let order: SortOrder = sort.ascending ? .forward : .reverse
    return switch sort.key {
      case .date: KeyPathComparator(\.date, order: order)
      case .sender: KeyPathComparator(\.displaySender, order: order)
      case .subject: KeyPathComparator(\.displaySubject, order: order)
    }
  }
}

/// How many of today's decisions sent mail to each place.
struct TodaySummary: Equatable {
  /// Records dated today.
  static var query: ActivityQuery {
    var query = ActivityQuery()
    query.start = Calendar.current.startOfDay(for: .now)
    return query
  }
  /// Decisions made today.
  var decisions = 0
  /// Today's Junk decisions.
  var junk = 0
  /// Today's Review decisions.
  var review = 0

  init() {}

  init(_ records: [DecisionRecord]) {
    decisions = records.count
    junk = records.count { $0.decision.label == .junk }
    review = records.count { $0.decision.label == .review }
  }
}
