import Foundation
import SpamWiseCore

/// A store in its own temporary directory, which is removed when the fixture is released.
final class TemporaryStore: Sendable {
  /// Where the store keeps its data.
  let url: URL
  let store: Store
  private let directory: URL

  init() throws {
    directory = FileManager.default.temporaryDirectory
      .appending(path: "SpamWise-UnitTests-\(UUID())")
    url = directory.appending(path: "state.store")
    store = try Store(url: url)
  }

  deinit { try? FileManager.default.removeItem(at: directory) }
}
