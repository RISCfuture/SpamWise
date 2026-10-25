import CryptoKit
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

  @Test
  func `restores message text only while this Mac retains reviewed text`() async throws {
    let message = try MIMEParser().parse(fixture("personal")).boundedForRetention()
    var state = backedUp
    state.reviewedLabels = [
      ReviewedLabel(
        identity: .init(accountID: "account-A", contentHash: message.hash),
        label: .inbox,
        message: message
      )
    ]
    let archive = try StateBackup.export(state, recoveryKey: key, includeContent: true)
    for retains in [false, true] {
      try await StateRepository.editSettings(store) {
        $0.advancedOptions.retainReviewedContent = retains
      }
      try await StateBackup.restore(archive, recoveryKey: key, store: store)
      let restored = try await StateRepository.load(store)
      #expect(restored.settings.advancedOptions.retainReviewedContent == retains)
      #expect(restored.reviewedLabels.map { $0.message != nil } == [retains])
    }
  }

  @Test
  func `leaves correction excerpts out of a backup without message text`() async throws {
    var state = backedUp
    state.corrections = [
      CorrectionExample(
        sender: "friend@example.org",
        domain: "example.org",
        subject: "Hello",
        excerpt: "Quoted body text",
        label: .inbox,
        promptScope: .account("account-A")
      )
    ]
    for (includeContent, excerpt) in [(false, ""), (true, "Quoted body text")] {
      let archive = try StateBackup.export(state, recoveryKey: key, includeContent: includeContent)
      try await StateBackup.restore(archive, recoveryKey: key, store: store)
      #expect(try await StateRepository.load(store).corrections.map(\.excerpt) == [excerpt])
    }
  }

  @Test
  func `restores trust exclusions and learning options a backup saved`() async throws {
    var state = backedUp
    state.settings.mailOptions.trustExclusions = ["alias@example.org"]
    state.settings.advancedOptions.bayes = true
    let archive = try StateBackup.export(state, recoveryKey: key)
    try await StateBackup.restore(archive, recoveryKey: key, store: store)
    let restored = try await StateRepository.load(store).settings
    #expect(restored.mailOptions.trustExclusions == ["alias@example.org"])
    #expect(restored.advancedOptions.bayes)
    #expect(!restored.advancedOptions.fingerprints && !restored.advancedOptions.learnedWeights)
  }

  @Test
  func `keeps this Mac's trust exclusions and learning options for a version-one backup`()
    async throws
  {
    try await StateRepository.editSettings(store) {
      $0.mailOptions.trustExclusions = ["alias@example.org"]
      $0.advancedOptions.fingerprints = true
    }
    try await StateBackup.restore(try versionOne(archive), recoveryKey: key, store: store)
    let restored = try await StateRepository.load(store)
    #expect(restored.rules == backedUp.rules)
    #expect(restored.settings.mailOptions.trustExclusions == ["alias@example.org"])
    #expect(restored.settings.advancedOptions.fingerprints)
  }

  /// Rewrites `archive` in the version-one format, which has no trust exclusions or learning options.
  private func versionOne(_ archive: Data) throws -> Data {
    let authentication = Data("SpamWise-backup-v1".utf8)
    let sealingKey = SymmetricKey(data: try #require(Data(base64Encoded: key)))
    let plain = try AES.GCM.open(
      AES.GCM.SealedBox(combined: archive),
      using: sealingKey,
      authenticating: authentication
    )
    var payload = try #require(JSONSerialization.jsonObject(with: plain) as? [String: Any])
    payload["version"] = 1
    payload.removeValue(forKey: "trustExclusions"); payload.removeValue(forKey: "learningOptions")
    return try #require(
      try AES.GCM.seal(
        JSONSerialization.data(withJSONObject: payload),
        using: sealingKey,
        authenticating: authentication
      ).combined
    )
  }
}
