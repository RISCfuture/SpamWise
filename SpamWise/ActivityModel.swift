import Foundation
import Observation
import SpamWiseCore

/**
 The Activity log as the table shows it: the newest matching records, fetched page by page from
 the store's indexed rows instead of filtering the whole log in memory.

 Without a store, as in previews, the model filters the fixture records it was given.
 */
@MainActor @Observable final class ActivityModel {
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
    guard let store else { throw IntegrationError.unavailable }
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
