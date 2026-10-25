import Foundation
import Testing
import SpamWiseCore
@testable import SpamWiseCommon

@MainActor
@Suite
struct `Optimistic settings edits` {
  private let temporary: TemporaryStore
  private var store: Store { temporary.store }

  init() throws { temporary = try TemporaryStore() }

  @Test
  func `survive a reload while their write is pending`() async throws {
    let shared = SharedStateModel(store: store)
    await shared.refresh()
    try await StateRepository.editSettings(store) { $0.policy = "Saved by another process" }
    shared.state.settings.policy = "Edited here"
    shared.settingsWritesInFlight = 1
    await shared.refresh()
    #expect(shared.settings.policy == "Edited here")
  }

  @Test
  func `show the stored value again once their write fails`() async throws {
    let shared = SharedStateModel(store: store)
    let settings = SettingsModel(shared: shared)
    await shared.refresh()
    let lock = try StoreLock(store)
    let write = settings.setSetting(\.paused, to: true)
    #expect(shared.settings.paused)
    await write.value
    lock.release()
    await shared.refresh()
    #expect(settings.saveFailure != nil)
    #expect(!shared.settings.paused)
  }

  @Test
  func `persist rapid edits in the order made`() async throws {
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

  @Test
  func `change only their own field and withdraw terms with the Spamhaus service`()
    async throws
  {
    let shared = SharedStateModel(store: store)
    let settings = SettingsModel(shared: shared)
    await shared.refresh()
    var accepted = ExternalEvidenceSettings()
    accepted.termsAcknowledged = true
    await settings.setSetting(\.advancedOptions.externalEvidence, to: accepted).value
    try await StateRepository.editSettings(store) { $0.policy = "Saved by another process" }
    settings.selectSpamhausService(.https)
    await settled(settings)
    let saved = try await StateRepository.load(store, StateSlices()).settings
    #expect(saved.policy == "Saved by another process")
    #expect(saved.advancedOptions.externalEvidence?.spamhausTransport == .https)
    #expect(saved.advancedOptions.externalEvidence?.termsAcknowledged == false)
  }

  @Test
  func `switch to the on-device model when filtering is kept on this Mac`() async throws {
    let shared = SharedStateModel(store: store)
    let settings = SettingsModel(shared: shared)
    await shared.refresh()
    settings.keepFilteringOnThisMac()
    await settled(settings)
    let saved = try await StateRepository.load(store, StateSlices()).settings
    #expect(saved.mailOptions.localOnly)
    #expect(saved.advancedOptions.model == .appleOnDevice)
    #expect(!settings.hasLocalOnlyConflict)
  }

  @Test
  func `save a stepper edit still waiting in its draft before quitting`() async throws {
    let shared = SharedStateModel(store: store)
    let settings = SettingsModel(shared: shared)
    await shared.refresh()
    let edited = shared.settings.correctionLimit + 1
    settings.correctionLimit.value = edited
    await settings.savePendingEdits()
    #expect(try await StateRepository.load(store, StateSlices()).settings.correctionLimit == edited)
    #expect(!settings.correctionLimit.hasUnsavedEdit)
  }

  /// Waits for every settings write queued so far.
  private func settled(_ settings: SettingsModel) async {
    await settings.editSettings { _ in }.value
  }
}

@MainActor
@Suite
struct `Set-aside storage` {
  private let temporary: TemporaryStore
  private var store: Store { temporary.store }

  init() throws { temporary = try TemporaryStore() }

  @Test
  func `asks for recovery when data is set aside after launch`() async throws {
    let shared = SharedStateModel(store: store)
    await shared.refresh()
    try await store.update("state.contacts", default: "unreadable") { _ in }
    try await StateRepository.update(store, loading: StateSlices([.contacts])) {
      $0.lastDigestWeek = "2026-W42"
    }
    await shared.refresh()
    #expect(shared.needsRecovery)
  }
}

@MainActor
@Suite
struct `Setting drafts` {
  @Test
  func `save a burst of edits once`() async {
    let setting = PersistedSetting()
    let draft = setting.draft()
    for value in 1...5 { draft.value = value }
    await draft.scheduledSave?.value
    #expect(setting.saves == [5])
    #expect(!draft.hasUnsavedEdit)
  }

  @Test
  func `follow the persisted value only while unedited`() {
    let setting = PersistedSetting()
    let draft = setting.draft()
    setting.value = 3
    #expect(draft.value == 3)
    draft.value = 4
    setting.value = 7
    #expect(draft.value == 4)
    draft.commit()
    #expect(setting.saves == [4])
  }

  @Test
  func `keep an unacceptable edit unsaved`() {
    let setting = PersistedSetting()
    let draft = setting.draft(accepting: 0...10)
    draft.value = 11
    draft.commit()
    #expect(setting.saves.isEmpty)
    #expect(draft.hasUnsavedEdit)
    #expect(!draft.isAcceptable)
    #expect(draft.value == 11)
  }
}

/// A stored setting that records each save.
@MainActor
private final class PersistedSetting {
  private static let debounce: Duration = .milliseconds(20)
  var value = 0
  private(set) var saves: [Int] = []

  func draft(accepting range: ClosedRange<Int> = Int.min...Int.max) -> SettingDraft<Int> {
    SettingDraft(
      delay: Self.debounce,
      persisted: { self.value },
      accepts: { range.contains($0) },
      save: { saved in
        self.saves.append(saved)
        self.value = saved
      }
    )
  }
}
