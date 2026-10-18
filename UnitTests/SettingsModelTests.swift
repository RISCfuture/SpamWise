import Foundation
import Testing
import SpamWiseCore
@testable import SpamWiseCommon

@MainActor @Suite
// swiftlint:disable:next type_name
struct `Optimistic settings edits` {
  @Test func `survive a reload while their write is pending`() async throws {
    let store = try temporaryStore()
    let shared = SharedStateModel(store: store)
    await shared.refresh()
    try await StateRepository.editSettings(store) { $0.policy = "Saved by another process" }
    shared.state.settings.policy = "Edited here"
    shared.settingsWritesInFlight = 1
    await shared.refresh()
    #expect(shared.settings.policy == "Edited here")
  }

  @Test func `persist rapid edits in the order made`() async throws {
    let store = try temporaryStore()
    let shared = SharedStateModel(store: store)
    let settings = SettingsModel(shared: shared)
    await shared.refresh()
    var last: Task<Void, Never>?
    for edit in 1...20 { last = settings.setSetting(\.policy, to: "Edit \(edit)") }
    await last?.value
    #expect(shared.settings.policy == "Edit 20")
    #expect(try await StateRepository.load(store, StateSlices()).settings.policy == "Edit 20")
    #expect(shared.settingsWritesInFlight == 0)
  }

  private func temporaryStore() throws -> Store {
    try Store(
      url: FileManager.default.temporaryDirectory
        .appending(path: "SpamWise-UnitTests-\(UUID())/state.store")
    )
  }
}
