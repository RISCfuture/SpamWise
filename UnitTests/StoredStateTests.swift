import Foundation
import Testing
import SpamWiseCore
@testable import SpamWiseCommon

@MainActor
@Suite
struct `First read of shared storage` {
  private let temporary: TemporaryStore
  private var store: Store { temporary.store }

  init() throws { temporary = try TemporaryStore() }

  @Test
  func `starts setup when nothing has been saved`() async {
    let shared = await firstRead()
    #expect(MainWindowContent(shared) == .setup)
    #expect(shared.isStorageReadable)
  }

  @Test
  func `says a newer version saved the data instead of starting setup`() async throws {
    try await store.update("state.schema", default: 0) { $0 = 3 }
    let shared = await firstRead()
    #expect(MainWindowContent(shared) == .newerVersion)
    #expect(!shared.isStorageReadable)
    #expect(!shared.canRetryLoading)
  }

  @Test
  func `reports a database that can't be opened instead of starting setup`() async throws {
    try Data("not a database".utf8).write(to: store.url)
    let shared = await firstRead()
    #expect(MainWindowContent(shared) == .unavailable)
    #expect(shared.storedStateError == .unreadable)
    #expect(!shared.isStorageReadable)
    #expect(shared.canRetryLoading)
  }

  @Test
  func `asks for recovery instead of starting setup when data was set aside`() async throws {
    try await store.update("application-v1", default: "not a snapshot") { _ in }
    let shared = await firstRead()
    #expect(MainWindowContent(shared) == .recovery)
    #expect(!shared.isStorageReadable)
  }

  @Test
  func `asks for recovery instead of starting setup when settings can't be decoded`()
    async throws
  {
    try await store.update("state.policy", default: "not settings") { _ in }
    let shared = await firstRead()
    #expect(MainWindowContent(shared) == .recovery)
    #expect(!shared.isStorageReadable)
  }

  private func firstRead() async -> SharedStateModel {
    let shared = SharedStateModel(store: store)
    await shared.refresh()
    return shared
  }
}

@Suite
struct `Retries while storage is locked` {
  private static let retry = LockRetry(delays: [.zero, .zero])

  @Test
  func `returns the first result read once the lock is free`() async throws {
    let attempts = Attempts()
    let result = try await Self.retry.run {
      try attempts.next(failing: 2, with: StoreError.lockUnavailable)
    }
    #expect(result == 3)
  }

  @Test
  func `gives up with the lock failure after its last retry`() async {
    let attempts = Attempts()
    await #expect(throws: StoreError.lockUnavailable) {
      try await Self.retry.run {
        try attempts.next(failing: .max, with: StoreError.lockUnavailable)
      }
    }
    #expect(attempts.count == 3)
  }

  @Test
  func `doesn't retry data it can't use`() async {
    let attempts = Attempts()
    await #expect(throws: StoredStateError.newerVersion) {
      try await Self.retry.run {
        try attempts.next(failing: .max, with: StoredStateError.newerVersion)
      }
    }
    #expect(attempts.count == 1)
  }

  /// Counts attempts, failing the first `failures` of them.
  private final class Attempts {
    private(set) var count = 0

    func next(failing failures: Int, with error: some Error) throws -> Int {
      count += 1
      guard count > failures else { throw error }
      return count
    }
  }
}
