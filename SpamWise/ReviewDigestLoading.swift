import Foundation
import SpamWiseCore

extension ReviewDigest {
  /// The identity of the current calendar week, as digests record it.
  static var currentWeek: String { ReviewDigest(state: AppState()).week }

  /// This week's digest, built from the last ``lookbackDays`` days of the Activity log.
  static func load(from store: Store, now: Date = .now) async throws -> ReviewDigest {
    var query = ActivityQuery()
    query.start = Calendar.current.date(byAdding: .day, value: -lookbackDays, to: now)
    var state = AppState()
    state.records = try await StateRepository.activity(
      store,
      matching: query,
      limit: RetentionLimits.activityRecords
    )
    return ReviewDigest(state: state, now: now)
  }
}
