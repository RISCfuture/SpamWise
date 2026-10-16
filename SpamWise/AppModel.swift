import SwiftUI
import SpamWiseCore
import MailIntegration

@MainActor @Observable final class AppModel {
  var state = AppState()
  var status = String(localized: "Ready for setup")
  var keyStatus = String(localized: "Key not verified in this session")
  var mailStatus = String(localized: "Mail connection not checked")
  var contactsStatus = String(localized: "Contacts optional — not requested")
  var busy = false
  var storageReady = false
  var accounts: [MailAccount] = []
  var showSetup = false
  var showDigest = false
  var store: Store?
  private var pipeline: Pipeline?
  private let adapter: AppleMailAdapter
  private let uiTesting: Bool
  private var work: Task<Void, Never>?
  private var lastScan = Date.distantPast
  private var lastContactsRefresh = Date.distantPast
  private var settingsWork: Task<Void, Never>?
  private var pendingSettings = 0
  init(preview: Bool = false) {
    uiTesting = preview || ProcessInfo.processInfo.arguments.contains("--ui-testing")
    #if DEBUG
      adapter = AppleMailAdapter(
        runner: uiTesting ? DeniedAppleEventRunner() : SystemAppleEventRunner()
      )
    #else
      adapter = AppleMailAdapter(runner: SystemAppleEventRunner())
    #endif
    do {
      let url =
        uiTesting
        ? FileManager.default.temporaryDirectory.appending(
          path: "SpamWise-UI-\(UUID())/state.store"
        ) : try Store.sharedURL()
      let store = try Store(url: url); self.store = store
      pipeline = Pipeline(
        store: store,
        classifier: ConfiguredClassifier(store: store),
        rdap: RDAPLookup(
          cacheURL: url.deletingLastPathComponent().appending(path: "rdap-cache.json")
        )
      )
      storageReady = true
    } catch {
      status =
        String(
          localized:
            "Shared storage unavailable. Check signing and App Group access; mail stays unchanged."
        )
    }
  }
  func refresh() async {
    guard let store else { return }
    do {
      var loaded = try await StateRepository.load(store)
      if pendingSettings > 0 { loaded.settings = state.settings }
      state = loaded
      if state.settings.advancedOptions.weeklyDigest, state.settings.onboardingComplete {
        let digest = ReviewDigest(state: state)
        if state.lastDigestWeek != digest.week, !digest.records.isEmpty {
          showDigest = true
          try await StateRepository.update(store) { $0.lastDigestWeek = digest.week }
        }
      }
    } catch {
      status = String(localized: "Shared storage unavailable; mail stays unchanged.")
    }
  }
  func monitor() async {
    #if DEBUG
      if uiTesting, ProcessInfo.processInfo.arguments.contains("--ui-corrections"), let store {
        do { try await UITestFixture.seedCorrections(in: store) } catch {
          status = String(localized: "Correction fixture could not be loaded.")
        }
      }
    #endif
    await refresh()
    while !Task.isCancelled {
      try? await Task.sleep(for: .seconds(3))
      guard !Task.isCancelled else { return }
      await refresh()
      if !uiTesting, !busy, state.settings.onboardingComplete,
        Date().timeIntervalSince(lastContactsRefresh) >= 3600
      {
        try? await refreshContacts()
      }
      if !uiTesting, !busy, state.settings.onboardingComplete,
        [.mailRule, .imap].contains(state.settings.route),
        !state.settings.paused, Date().timeIntervalSince(lastScan) > 60
      {
        scan(dryRun: state.settings.dryRun, automatic: true)
      }
    }
  }
  func editSettings(_ edit: @escaping @Sendable (inout SpamWiseCore.Settings) -> Void) {
    guard let store else { return }
    edit(&state.settings)
    pendingSettings += 1
    let previous = settingsWork
    settingsWork = Task {
      await previous?.value
      do { try await StateRepository.editSettings(store, edit) } catch {
        status = String(localized: "Settings could not be saved; mail stays unchanged.")
      }
      pendingSettings -= 1
      await refresh()
    }
  }
  func setSetting<T: Sendable>(
    _ key: any WritableKeyPath<SpamWiseCore.Settings, T> & Sendable,
    to value: T
  ) {
    editSettings { $0[keyPath: key] = value }
  }
  func finishSetup() {
    editSettings {
      $0.onboardingComplete = true; $0.dryRun = true
    }
    showSetup = false
  }
  func togglePause() {
    setSetting(\.paused, to: !state.settings.paused)
  }
  func cancel() {
    work?.cancel()
    status = String(
      localized: "Cancelling; mail stays unchanged unless an action was already requested."
    )
  }
  func run(_ operation: @escaping @MainActor () async throws -> Void) {
    guard !busy else { return }; busy = true
    work = Task {
      defer { busy = false }
      do { try await operation() } catch { status = Self.describe(error) }
      await refresh()
    }
  }
  func checkMail() {
    run { [self] in
      do {
        if uiTesting { throw IntegrationError.permissionDenied }
        mailStatus = String(localized: "Waiting for Mail Automation permission…")
        try await SystemAppleEventRunner.requestMailPermission()
        accounts = try await adapter.accounts()
        mailStatus =
          String(
            localized:
              "Connected — \(accounts.count) accounts readable. Actions need a disposable-message test."
          )
        status = String(localized: "Mail connection checked")
      } catch { mailStatus = Self.describe(error); throw error }
    }
  }
  func requestContacts() {
    run { [self] in
      try await refreshContacts(requestAccess: true)
    }
  }
  private func refreshContacts(requestAccess: Bool = false) async throws {
    lastContactsRefresh = .now
    do {
      let addresses = try await ContactsLookup().addresses(requestAccess: requestAccess)
      if let store {
        try await StateRepository.update(store) {
          $0.contactAddresses = addresses; $0.contactsUpdatedAt = .now
        }
      }
      contactsStatus =
        addresses == nil
        ? String(localized: "Contacts unavailable — relationship remains unknown")
        : String(localized: "Contacts refreshed")
    } catch {
      contactsStatus = String(
        localized: "Contacts refresh failed — cached evidence expires after 24 hours"
      )
      throw error
    }
  }
  private func maintainHistory() async {
    guard let store else { return }
    do {
      let current = try await StateRepository.load(store)
      let eligible = Set(
        current.records.filter {
          $0.decision.label == .inbox && $0.outcome != .superseded
        }.map { $0.identity.key }
      ).subtracting(current.retries.map { $0.identity.key })
      let histories: [String: HistoryIndex]
      if state.settings.advancedOptions.transport == .imap {
        histories = try await configuredIMAPAdapter().importHistory()
      } else {
        histories = try await adapter.importHistory(
          previous: current.histories,
          eligibleInbox: eligible,
          incremental: true
        )
      }
      try await StateRepository.update(store) { state in
        for (account, history) in histories { state.histories[account] = history }
      }
    } catch {
      mailStatus = String(
        localized: "History refresh unavailable — only previously stored relationships are known"
      )
    }
  }
  func importHistory() {
    run { [self] in
      let histories: [String: HistoryIndex]
      if state.settings.advancedOptions.transport == .imap {
        histories = try await configuredIMAPAdapter().importHistory()
      } else {
        histories = try await adapter.importHistory(previous: state.histories)
      }
      if let store {
        try await StateRepository.update(store) { state in
          for (account, imported) in histories { state.histories[account] = imported }
        }
      }
      status = String(
        localized: "Imported bounded Inbox and Sent history; remaining history is unknown."
      )
    }
  }
  func testDisposableMessage() {
    run { [self] in
      do {
        mailStatus =
          String(
            localized:
              "Testing the selected message; allowing 30 seconds after each move for Mail to sync…"
          )
        let account = try await adapter.testDisposableMessage()
        if let store {
          try await StateRepository.update(store) { state in
            state.settings.validatedAccounts.insert(account); state.settings.route = .mailRule
            state.revision += 1
          }
        }
        mailStatus =
          String(localized: "Junk, Inbox restoration, and orange flag verified in Mail.")
        status = mailStatus
      } catch { mailStatus = Self.describe(error); throw error }
    }
  }
  func scan(dryRun: Bool = true, automatic: Bool = false, limit: Int = 20) {
    guard let pipeline else { return }
    if automatic
      && (!state.settings.onboardingComplete || ![.mailRule, .imap].contains(state.settings.route)
        || state.settings.paused)
    {
      return
    }
    run { [self] in
      lastScan = .now
      if !uiTesting, Date().timeIntervalSince(lastContactsRefresh) >= 3600 {
        try? await refreshContacts()
      }
      if automatic { await maintainHistory() }
      await refresh()
      let activeAdapter: any MailClientAdapter
      let messages: [MailEnvelope]
      var retryAccountID: String?
      if state.settings.advancedOptions.transport == .imap {
        let imap = try await configuredIMAPAdapter()
        activeAdapter = imap
        retryAccountID = imap.accountID
        messages =
          try await
          (automatic
          ? imap.nextInboxMessages(limit: limit, cursorStore: store)
          : imap.recentMessages(limit: limit))
      } else {
        activeAdapter = adapter
        messages =
          try await
          (automatic
          ? adapter.nextInboxMessages(limit: limit) : adapter.recentMessages(limit: limit))
      }
      let seen = Set(state.records.map { $0.identity.key })
      var count = 0
      for message in messages where !automatic || !seen.contains(message.identity.key) {
        try Task.checkCancellation()
        _ = await pipeline.process(message, adapter: activeAdapter, forceDryRun: dryRun)
        count += 1; status = String(localized: "Classified \(count) of \(messages.count) messages")
        await refresh()
      }
      if !dryRun { await pipeline.retryDue(adapter: activeAdapter, accountID: retryAccountID) }
      status =
        dryRun
        ? String(localized: "Dry run finished — no mail actions requested")
        : String(localized: "Mail check finished")
    }
  }
  func correct(_ record: DecisionRecord, label: MailLabel, scope: RuleScope = .address) {
    guard let pipeline else { return }
    run { [self] in
      let activeAdapter: (any MailClientAdapter)?
      if record.identity.mailboxValidity != nil {
        activeAdapter = try? await configuredIMAPCorrectionAdapter()
      } else {
        activeAdapter = adapter
      }
      let result = try await pipeline.correct(
        recordID: record.id,
        label: label,
        scope: scope,
        adapter: activeAdapter
      )
      status =
        String(localized: "Correction saved. Mail action: \(result.outcome.localizedTitle).")
        + (result.actionError.map { " " + $0 } ?? "")
    }
  }
  func handle(_ url: URL) {
    guard url.scheme == "spamwise", url.host == "check-inbox" else { return }
    scan(dryRun: state.settings.dryRun, automatic: true)
  }
  func revealRule() {
    guard let url = Bundle.main.url(forResource: "SpamWiseRule", withExtension: "scpt") else {
      status = String(localized: "Rule script missing from app bundle"); return
    }
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }
  static func describe(_ error: any Error) -> String {
    if error as? IntegrationError == .permissionDenied {
      return
        String(
          localized:
            "Automation permission denied. Allow SpamWise in System Settings → Privacy & Security → Automation."
        )
    }
    if let error = error as? IntegrationError {
      return String(localized: "Mail action unavailable: \(error.rawValue).")
    }
    if let error = error as? ClassificationError {
      return String(
        localized: "Classification unavailable: \(error.rawValue). Mail was left unchanged."
      )
    }
    if let error = error as? BudgetError { return error.localizedDescription }
    if let error = error as? RuleManagementError { return error.localizedDescription }
    if let error = error as? IMAPError {
      return String(localized: "IMAP operation failed: \(error.rawValue).")
    }
    if error is KeychainError {
      return String(
        localized: "Keychain unavailable. Check the signed app’s shared Keychain entitlement."
      )
    }
    if error is CancellationError {
      return String(localized: "Cancelled — no further actions requested.")
    }
    return String(
      localized: "Operation unavailable. Mail stays unchanged; check Help for troubleshooting."
    )
  }
  var today: [DecisionRecord] { state.records.filter { Calendar.current.isDateInToday($0.date) } }
  var monthCost: Double {
    state.costByMonth?[AppState.monthKey(.now)]
      ?? state.records.filter {
        Calendar.current.isDate($0.date, equalTo: .now, toGranularity: .month)
      }.reduce(0) { $0 + ($1.verdict?.usage.estimatedCost ?? 0) }
  }
}
