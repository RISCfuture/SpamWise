import Foundation
import Testing
import SpamWiseCore

@Suite
struct `Encrypted state backup` {
  private let store: Store
  private let backedUp: AppState
  private let reservation: SpendingReservation
  private let key = StateBackup.recoveryKey()
  private let archive: Data

  /// Backs up live-filtering state with one Allow rule and a spending reservation.
  init() async throws {
    store = try testStore()
    try await enableActions(store)
    try await RuleManagement.save(
      scope: .address,
      value: "friend@example.org",
      disposition: .allow,
      store: store
    )
    reservation = try await SpendingLimit.reserve(usd: 1, store: store)
    backedUp = try await StateRepository.load(store)
    archive = try StateBackup.export(backedUp, recoveryKey: key)
  }

  @Test
  func `encrypts the archive`() {
    #expect(!archive.contains(Data("friend@example.org".utf8)))
  }

  @Test
  func `rejects a different recovery key without changing state`() async throws {
    await #expect(throws: BackupError.self) {
      try await StateBackup.restore(archive, recoveryKey: StateBackup.recoveryKey(), store: store)
    }
    #expect(try await StateRepository.load(store).revision == backedUp.revision)
  }

  @Test
  func `rejects a damaged archive without changing state`() async throws {
    var damaged = archive; damaged[0] ^= 1
    await #expect(throws: BackupError.self) {
      try await StateBackup.restore(damaged, recoveryKey: key, store: store)
    }
    #expect(try await StateRepository.load(store).revision == backedUp.revision)
  }

  @Test
  func `rejects corrections that exceed their bounds or quote every account unlinked`()
    async throws
  {
    let valid = CorrectionExample(
      sender: "friend@example.org",
      domain: "example.org",
      subject: "Hello",
      excerpt: "",
      label: .inbox,
      promptScope: .account("account-A")
    )
    var oversized = valid, unlinked = valid
    oversized.subject = String(repeating: "a", count: 101)
    unlinked.promptScope = .everyAccount
    for invalid in [[oversized], [unlinked], [valid, valid]] {
      var state = backedUp
      state.corrections = invalid
      let archive = try StateBackup.export(state, recoveryKey: key)
      await #expect(throws: BackupError.self) {
        try await StateBackup.restore(archive, recoveryKey: key, store: store)
      }
    }
    #expect(try await StateRepository.load(store).revision == backedUp.revision)
  }

  @Test
  func `restores rules with actions disabled and spending preserved`() async throws {
    try await StateRepository.update(store, loading: StateSlices([.contentRules])) {
      $0.contentRuleHits[UUID()] = 3
    }
    try await StateBackup.restore(archive, recoveryKey: " \(key)\n", store: store)
    let restored = try await StateRepository.load(store)
    #expect(restored.rules == backedUp.rules)
    #expect(restored.contentRuleHits.isEmpty)
    #expect(restored.settings.paused && restored.settings.dryRun)
    #expect(restored.settings.validatedAccounts.isEmpty)
    #expect(try await SpendingLimit.load(store).committedMicroUSD == reservation.microUSD)
  }
}
