import Foundation
import Testing
import SpamWiseCore

private let utcCalendar: Calendar = {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(secondsFromGMT: 0)!
  return calendar
}()

@Test(arguments: [
  (start: 22, end: 8, hour: 23, quiet: true), (22, 8, 7, true), (22, 8, 12, false),
  (9, 17, 12, true), (9, 17, 17, false), (0, 0, 3, false), (24, 8, 12, true)
])
func `treats hours in an overnight or daytime period, or any invalid hour, as quiet`(
  start: Int,
  end: Int,
  hour: Int,
  quiet: Bool
) throws {
  var preferences = NotificationPreferences()
  preferences.quietStartHour = start; preferences.quietEndHour = end
  let date = try #require(
    utcCalendar.date(bySettingHour: hour, minute: 0, second: 0, of: Date(timeIntervalSince1970: 0))
  )
  #expect(preferences.isQuiet(at: date, calendar: utcCalendar) == quiet)
}

@Suite
// swiftlint:disable:next type_name
struct `Notification batches` {
  private static let now = Date(timeIntervalSince1970: 1_800_014_400)
  private let store: Store

  /// Enables notifications an hour ago without quiet hours, then records one applied Review decision.
  init() async throws {
    store = try testStore()
    var preferences = NotificationPreferences()
    preferences.enabledSince = Self.now.addingTimeInterval(-3600)
    preferences.quietStartHour = 0; preferences.quietEndHour = 0
    let configured = preferences
    try await StateRepository.update(store) { state in
      state.settings.dryRun = false
      state.settings.mailOptions.notifications = configured
      var record = DecisionRecord(
        identity: .init(accountID: "a", contentHash: "review"),
        sender: "private@example.org",
        subject: "Private subject",
        decision: .init(label: .review, action: .orangeFlag, reason: .model("uncertain")),
        outcome: .applied,
        path: .model,
        revision: 0
      )
      record.date = Self.now.addingTimeInterval(-60)
      state.records = [record]
    }
  }

  private func claim(_ store: Store, after seconds: TimeInterval = 0) async throws
    -> NotificationBatch?
  {
    try await NotificationPlanning.claim(
      store: store,
      now: Self.now.addingTimeInterval(seconds),
      calendar: utcCalendar
    )
  }

  @Test func `counts unresolved Review without announcing Inbox by default`() async throws {
    let batch = try #require(await claim(store))
    #expect(batch.review == 1 && batch.good == 0)
  }

  @Test func `announces a decision once across restarts`() async throws {
    _ = try await claim(store)
    #expect(try await claim(Store(url: store.url), after: 4000) == nil)
  }

  @Test(arguments: [false, true])
  func `announces a later Review decision unless it was corrected`(corrected: Bool) async throws {
    _ = try await claim(store)
    try await StateRepository.update(store) { state in
      var record = state.records[0]
      record.id = UUID(); record.identity.contentHash = "later"
      record.correctedLabel = corrected ? .inbox : nil
      state.records.append(record)
    }
    #expect(try await claim(store, after: 5000)?.review == (corrected ? nil : 1))
  }
}
