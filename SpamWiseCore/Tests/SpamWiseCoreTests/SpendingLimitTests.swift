import Foundation
import Testing
import SpamWiseCore

@Suite
// swiftlint:disable:next type_name
struct `Monthly spending limit` {
  private static let october = Date(timeIntervalSince1970: 1_792_000_000)
  private static let november = Date(timeIntervalSince1970: 1_794_700_000)
  private static let reservationUSD = 0.10, reservationMicroUSD: UInt64 = 100_000
  private let store: Store

  /// Sets a $0.25 limit in October, which fits two $0.10 reservations.
  init() async throws {
    store = try testStore()
    try await SpendingLimit.setLimit(usd: 0.25, store: store, at: Self.october)
  }

  private func reserve(_ usd: Double = Self.reservationUSD, at date: Date = Self.october)
    async throws
    -> SpendingReservation
  {
    try await SpendingLimit.reserve(usd: usd, store: store, at: date)
  }

  @Test func `bounds concurrent reservations by the limit`() async throws {
    let store = store
    let outcomes = await withTaskGroup(of: (any Error)?.self, returning: [(any Error)?].self) {
      group in
      for _ in 0..<8 {
        group.addTask {
          do {
            _ = try await SpendingLimit.reserve(
              usd: Self.reservationUSD,
              store: store,
              at: Self.october
            )
            return nil
          } catch { return error }
        }
      }
      return await group.reduce(into: []) { $0.append($1) }
    }
    let successes = outcomes.filter { $0 == nil }.count
    #expect(
      outcomes.compactMap { $0 }.allSatisfy {
        $0 as? SpendingLimitError == .limitReached || $0 is StoreError
      }
    )
    #expect(successes <= 2)
    #expect(
      try await SpendingLimit.load(store, at: Self.october).committedMicroUSD
        == UInt64(successes) * Self.reservationMicroUSD
    )
  }

  @Test func `refuses a reservation beyond the limit`() async throws {
    for _ in 0..<2 { _ = try await reserve() }
    await #expect(throws: SpendingLimitError.limitReached) { _ = try await reserve() }
    let spending = try await SpendingLimit.load(store, at: Self.october)
    #expect(spending.committedMicroUSD == 2 * Self.reservationMicroUSD)
    #expect(spending.limitReached)
  }

  @Test func `accepts a smaller reservation that still fits`() async throws {
    for _ in 0..<2 { _ = try await reserve() }
    _ = try await reserve(0.05)
    #expect(try await !SpendingLimit.load(store, at: Self.october).limitReached)
  }

  @Test func `starts a new month with the same limit and settles measured cost`() async throws {
    for _ in 0..<2 { _ = try await reserve() }
    let reservation = try await reserve(at: Self.november)
    try await SpendingLimit.settle(reservation, costUSD: 0.000_138, store: store)
    let spending = try await SpendingLimit.load(store, at: Self.november)
    #expect(spending.limitMicroUSD == 250_000 && !spending.limitReached)
    #expect(spending.committedMicroUSD == 138 && spending.requests == 1)
  }

  @Test(arguments: [Double.nan, 20_000_000_000_000])
  func `rejects an invalid limit`(_ usd: Double) async {
    await #expect(throws: SpendingLimitError.invalidAmount) {
      try await SpendingLimit.setLimit(usd: usd, store: store)
    }
  }

  @Test func `records one deferred decision however often refused mail is swept`() async throws {
    let refused = Pipeline(
      store: store,
      classifier: MockClassifier(operation: { _ in throw SpendingLimitError.limitReached })
    )
    for _ in 0..<2 {
      let swept = try await refused.processBatch(
        [envelope()],
        adapter: nil,
        dryRun: true,
        skipsSettled: true
      )
      #expect(swept.count == 1)
    }
    let deferred = try await StateRepository.load(store).records
    #expect(deferred.count == 1 && deferred.allSatisfy(\.deferredBySpendingLimit))
  }
}
