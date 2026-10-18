import Foundation
import Observation
import SpamWiseCore

/**
 The interface's copy of shared storage, reloaded slice by slice as change tokens move.

 The Activity log is not copied: ``recordsVersion`` changes whenever it does, and views page
 through it with ``ActivityModel``.
 */
@MainActor @Observable final class SharedStateModel {
  /// Presented parts and the change tokens that cover them; learning and claims stay in the store.
  private static let presentedParts: [(StateSlices.Parts, Set<StateSlice>)] = [
    (.rules, [.rules]), (.contentRules, [.contentRules, .contentRuleHits, .contentRuleSkips]),
    (.corrections, [.corrections]), (.audit, [.audit]), (.undo, [.undo]),
    (.contacts, [.contacts])
  ]
  private static let digestCheckInterval: Duration = .seconds(3600)
  private static let folderHealthKeyPrefix = "folder:"
  /// Settings, rules and other presented state; `records` stays empty.
  var state = AppState()
  /// Scan health of each account and folder plan.
  var scanHealth: [String: MailScanHealth] = [:]
  /// This month's spending ledger, or nil when it could not be read.
  var spending: MonthlySpending?
  /// Whether the first reload finished.
  private(set) var hasLoadedState: Bool
  /// Whether settings were read from storage, so edits never write defaults over them.
  private(set) var hasLoadedSettings: Bool
  /// Shared storage problems the user should know about.
  private(set) var storageStatus: OperationStatus?
  /// Changes whenever the Activity log does.
  private(set) var recordsVersion = 0
  /// This week's unseen Review digest, announced instead of presented.
  private(set) var pendingDigest: ReviewDigest?
  /// Settings writes still in flight; while any are, reloads keep the edited settings.
  var settingsWritesInFlight = 0
  @ObservationIgnored let store: Store?
  @ObservationIgnored private var changeTokens: [StateSlice: Int] = [:]
  @ObservationIgnored private var spendingToken: Int?
  @ObservationIgnored private var lastDigestCheck: (week: String, time: ContinuousClock.Instant)?
  @ObservationIgnored private var needsRecovery = false

  var settings: SpamWiseCore.Settings { state.settings }
  var monthCost: Double { state.costByMonth[AppState.monthKey(.now), default: 0] }
  var spendingLimitReached: Bool {
    spending?.limitReached == true
      && [.claude, .openAI, .gemini].contains(state.settings.advancedOptions.backend)
  }
  /// Accounts with recorded scan health, by display name.
  var knownAccounts: [(id: String, name: String)] {
    scanHealth.filter { !$0.key.hasPrefix(Self.folderHealthKeyPrefix) }
      .map { (id: $0.key, name: $0.value.accountName) }
      .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  /**
   Creates the mirror of `store`.

   - Parameters:
     - store: Shared storage, or nil when it could not be opened.
     - reportsMissingStore: Whether a missing store is reported to the user; previews have none.
   */
  init(store: Store?, reportsMissingStore: Bool = true) {
    self.store = store
    hasLoadedState = store == nil
    hasLoadedSettings = store == nil && !reportsMissingStore
    if store == nil, reportsMissingStore {
      storageStatus = .failure(OperationFailure(SharedStorageError.unavailable))
    }
  }

  /// Reloads only the slices whose change tokens moved, and publishes only real differences.
  func refresh() async {
    defer { hasLoadedState = true }
    guard let store else { return }
    do {
      try await reloadChangedSlices(from: store)
      hasLoadedSettings = true
      await reloadSpendingIfChanged(from: store)
      try await checkDigest(store)
      if case .failure = storageStatus, !needsRecovery { storageStatus = nil }
    } catch {
      storageStatus = .failure(OperationFailure(error))
    }
  }

  /// Records that the user opened this week's digest, so it is no longer announced.
  func markDigestSeen(_ digest: ReviewDigest) async {
    pendingDigest = nil
    guard state.lastDigestWeek != digest.week else { return }
    state.lastDigestWeek = digest.week
    guard let store else { return }
    try? await StateRepository.update(store, loading: StateSlices()) {
      $0.lastDigestWeek = digest.week
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
    if settingsWritesInFlight > 0 { next.settings = state.settings }
    if next != state { state = next }
    if changed.contains(.mailHealth) {
      let health = try await MailHealthRepository.load(store)
      if health != scanHealth { scanHealth = health }
    }
    if changed.contains(.records) { recordsVersion += 1 }
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
    needsRecovery = try await !StateRecovery.entries(store).isEmpty
    guard needsRecovery else { return }
    let message = String(
      localized:
        "Some saved SpamWise data couldn’t be read and was set aside. Restore a backup, or keep the current settings."
    )
    storageStatus = .failure(OperationFailure(message: message))
  }

  /// Announces this week's digest once it has unresolved Review items; checks at most hourly.
  private func checkDigest(_ store: Store) async throws {
    guard state.settings.advancedOptions.weeklyDigest, state.settings.onboardingComplete else {
      pendingDigest = nil
      lastDigestCheck = nil
      return
    }
    let week = ReviewDigest.currentWeek, now = ContinuousClock.now
    if let lastDigestCheck, lastDigestCheck.week == week,
      now - lastDigestCheck.time < Self.digestCheckInterval
    {
      return
    }
    lastDigestCheck = (week, now)
    let digest = try await ReviewDigest.load(from: store)
    pendingDigest = state.lastDigestWeek != digest.week && !digest.records.isEmpty ? digest : nil
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
    return next
  }
}
