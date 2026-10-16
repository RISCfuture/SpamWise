import Foundation
import Testing
import SpamWiseCore
@testable import SpamWiseCommon

@Suite
struct `Aggregate filtering state` {
  @Test(arguments: [FilteringStatus.setupIncomplete, .paused, .mailNotAuthorized, .mailNotRunning])
  func `keeps a stopped status ahead of network and check problems`(status: FilteringStatus) {
    let state = FilteringState(status, needsNetwork: true, isOnline: false, isFailing: true)
    #expect(state.rawValue == status.rawValue)
  }

  @Test(arguments: [FilteringStatus.rolesNotValidated, .dryRun, .filtering])
  func `reports offline before failing checks while checks run`(status: FilteringStatus) {
    #expect(
      FilteringState(status, needsNetwork: true, isOnline: false, isFailing: true) == .offline
    )
    #expect(
      FilteringState(status, needsNetwork: true, isOnline: true, isFailing: true) == .failing
    )
  }

  @Test
  func `ignores the network when checks stay on this Mac`() {
    let state = FilteringState(.dryRun, needsNetwork: false, isOnline: false, isFailing: false)
    #expect(state == .dryRun)
  }

  @Test
  func `needs the network unless Apple Mail and the on-device model are selected`() {
    var settings = Settings()
    settings.advancedOptions.backend = .onDevice
    #expect(!settings.checksNeedNetwork)
    settings.advancedOptions.transport = .imap
    #expect(settings.checksNeedNetwork)
  }
}

@Suite
struct `Activity table sorting` {
  @Test(arguments: [ActivitySort.Key.date, .sender, .subject], [true, false])
  func `asks the store for the order each column header shows`(
    key: ActivitySort.Key,
    ascending: Bool
  ) {
    let order = ActivitySort(key: key, ascending: ascending)
    #expect(ActivitySortColumn.sort(for: ActivitySortColumn.comparator(for: order)) == order)
  }

  @Test
  func `falls back to newest first for a column the store can’t order`() {
    let revision = KeyPathComparator(\DecisionRecord.revision, order: .forward)
    #expect(ActivitySortColumn.sort(for: revision) == ActivitySort())
  }
}

@Suite
struct `Activity date format` {
  private static let utc = TimeZone(identifier: "UTC") ?? .gmt
  private static let today = Date(timeIntervalSince1970: 1_791_000_000)
  private let style = ActivityDateStyle(
    today: today,
    locale: Locale(identifier: "en_US"),
    calendar: Calendar(identifier: .gregorian),
    timeZone: utc
  )

  @Test
  func `shows only the time for today`() {
    let formatted = style.format(Self.today.addingTimeInterval(-60))
    #expect(!formatted.contains("/"))
    #expect(formatted.contains(":"))
  }

  @Test
  func `adds the date for earlier days`() {
    let formatted = style.format(Self.today.addingTimeInterval(-2 * 86_400))
    #expect(formatted.contains("/"))
    #expect(formatted.contains(":"))
  }
}
