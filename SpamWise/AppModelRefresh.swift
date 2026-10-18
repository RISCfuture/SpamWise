import Foundation
import SpamWiseCore

extension AppModel {
  /// Presented parts and the change tokens that cover them; learning and claims stay in the store.
  private static let presentedParts: [(StateSlices.Parts, Set<StateSlice>)] = [
    (.rules, [.rules]), (.contentRules, [.contentRules, .contentRuleHits, .contentRuleSkips]),
    (.corrections, [.corrections]), (.audit, [.audit]), (.undo, [.undo]),
    (.contacts, [.contacts])
  ]
  private static func merged(_ records: [DecisionRecord], _ updates: [DecisionRecord])
    -> [DecisionRecord]
  {
    var byID = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
    for record in updates { byID[record.id] = record }
    return Array(byID.values.sorted { $0.date < $1.date }.suffix(RetentionLimits.activityRecords))
  }
  /// Reloads only the slices whose change tokens moved, and publishes only real differences.
  func refresh() async {
    defer { hasLoadedState = true }
    guard let store else { return }
    do {
      try await reloadChangedSlices(from: store)
      await reloadSpendingIfChanged(from: store)
      try await presentDigestIfDue(store)
    } catch {
      status = String(localized: "Shared storage unavailable; mail stays unchanged.")
    }
  }
  private func reloadChangedSlices(from store: Store) async throws {
    let tokens = try await StateRepository.changeTokens(store)
    let changed = Set(
      StateSlice.allCases.filter { changeTokens.isEmpty || tokens[$0] != changeTokens[$0] }
    )
    guard !changed.isEmpty else { return }
    if changeTokens.isEmpty { try await checkRecovery(store) }
    var next = try await reloadedState(changed, from: store)
    if pendingSettings > 0 { next.settings = state.settings }
    if next != state { state = next }
    if changed.contains(.mailHealth) {
      let health = try await MailHealthRepository.load(store)
      if health != scanHealth { scanHealth = health }
    }
    changeTokens = tokens
  }
  /// Reloads the spending ledger after a write or a new month, keeping it while the store is busy.
  private func reloadSpendingIfChanged(from store: Store) async {
    do {
      let token = try await SpendingLimit.changeToken(store)
      guard spendingIsStale(token: token) else { return }
      spending = try await SpendingLimit.load(store)
      spendingToken = token
    } catch StoreError.lockUnavailable {
    } catch {
      spending = nil
    }
  }
  private func spendingIsStale(token: Int?) -> Bool {
    guard let spending else { return true }
    return token != spendingToken || spending.month != BillingMonth(containing: .now)
  }
  private func checkRecovery(_ store: Store) async throws {
    recoveryNeeded = try await !StateRecovery.entries(store).isEmpty
    guard recoveryNeeded else { return }
    status = String(
      localized:
        "Some saved SpamWise data couldn’t be read and was set aside. Restore a backup, or keep the current settings."
    )
  }
  private func presentDigestIfDue(_ store: Store) async throws {
    guard state.settings.advancedOptions.weeklyDigest, state.settings.onboardingComplete else {
      return
    }
    let digest = ReviewDigest(state: state)
    guard state.lastDigestWeek != digest.week, !digest.records.isEmpty else { return }
    showDigest = true
    try await StateRepository.update(store, loading: StateSlices()) {
      $0.lastDigestWeek = digest.week
    }
  }
  private func reloadedState(_ changed: Set<StateSlice>, from store: Store) async throws
    -> AppState
  {
    let parts = Self.presentedParts.filter { !$0.1.isDisjoint(with: changed) }.reduce(
      into: StateSlices.Parts()
    ) { $0.formUnion($1.0) }
    let loaded = try await StateRepository.load(
      store,
      StateSlices(
        parts,
        retries: changed.contains(.retries) ? .all : .none,
        histories: changed.contains(.histories) ? .all : .none,
        reviewedLabels: changed.contains(.reviewedLabels) ? .all : .none
      )
    )
    var next = state
    next.revision = loaded.revision; next.settings = loaded.settings
    next.costByMonth = loaded.costByMonth; next.lastDigestWeek = loaded.lastDigestWeek
    if parts.contains(.rules) { next.rules = loaded.rules }
    if parts.contains(.contentRules) {
      next.contentRules = loaded.contentRules; next.contentRuleHits = loaded.contentRuleHits
      next.contentRuleSkips = loaded.contentRuleSkips
    }
    if parts.contains(.corrections) { next.corrections = loaded.corrections }
    if parts.contains(.audit) { next.auditEvents = loaded.auditEvents }
    if parts.contains(.undo) { next.correctionUndo = loaded.correctionUndo }
    if parts.contains(.contacts) {
      next.contactAddresses = loaded.contactAddresses
      next.contactsUpdatedAt = loaded.contactsUpdatedAt; next.ownAddresses = loaded.ownAddresses
    }
    if changed.contains(.retries) { next.retries = loaded.retries }
    if changed.contains(.histories) { next.histories = loaded.histories }
    if changed.contains(.reviewedLabels) { next.reviewedLabels = loaded.reviewedLabels }
    if changed.contains(.records) {
      let update = try await StateRepository.recordChanges(store, after: recordStamp)
      recordStamp = update.stamp
      next.records = Self.merged(next.records, update.records)
    }
    return next
  }
}
