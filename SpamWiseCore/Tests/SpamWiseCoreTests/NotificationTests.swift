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

@Test(arguments: [
  (json: #"{"quietStartHour":0,"quietEndHour":0}"#, enabled: false, start: 22, end: 8),
  (#"{"quietStartHour":9,"quietEndHour":17}"#, true, 9, 17),
  (#"{"quietHoursEnabled":false,"quietStartHour":9,"quietEndHour":17}"#, false, 9, 17)
])
func `keeps quiet hours that are turned off, reading equal hours as off`(
  json: String,
  enabled: Bool,
  start: Int,
  end: Int
) throws {
  let preferences = try JSONDecoder().decode(NotificationPreferences.self, from: Data(json.utf8))
  #expect(preferences.quietHoursEnabled == enabled)
  #expect((preferences.quietStartHour, preferences.quietEndHour) == (start, end))
}

@Suite
struct `Notification batches` {
  private static let now = Date(timeIntervalSince1970: 1_800_014_400)
  private let store: Store

  /// Enables notifications an hour ago with quiet hours from noon turned off, then records one
  /// applied Review decision.
  init() async throws {
    store = try testStore()
    var preferences = NotificationPreferences()
    preferences.enabledSince = Self.now.addingTimeInterval(-3600)
    preferences.quietHoursEnabled = false; preferences.quietStartHour = 12
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

  /// Claims with the stored settings, or with them changed by `edit`.
  private func claim(
    _ store: Store,
    after seconds: TimeInterval = 0,
    editing edit: (inout Settings) -> Void = { _ in }
  ) async throws -> NotificationBatch? {
    var settings = try await StateRepository.load(store, StateSlices()).settings
    edit(&settings)
    return try await NotificationPlanning.claim(
      store: store,
      settings: settings,
      now: Self.now.addingTimeInterval(seconds),
      calendar: utcCalendar
    )
  }

  @Test
  func `counts unresolved Review without announcing Inbox by default`() async throws {
    let batch = try #require(await claim(store))
    #expect(batch.review == 1 && batch.good == 0)
  }

  @Test(arguments: Hold.allCases)
  func `holds the batch while filtering is paused, in a dry run or in quiet hours`(
    hold: Hold
  ) async throws {
    #expect(try await claim(store, editing: hold.apply(to:)) == nil)
    #expect(try await claim(store)?.review == 1)
  }

  @Test
  func `announces a decision once across restarts`() async throws {
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

  /// A setting that keeps a due batch from being announced yet.
  enum Hold: CaseIterable, Sendable {
    case paused, dryRun, quietHours

    func apply(to settings: inout Settings) {
      switch self {
        case .paused: settings.paused = true
        case .dryRun: settings.dryRun = true
        case .quietHours: settings.mailOptions.notifications.quietHoursEnabled = true
      }
    }
  }
}
