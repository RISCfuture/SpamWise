import SwiftUI
import SpamWiseCore
import MailIntegration

@MainActor @Observable final class AppModel {
  private static let monitorInterval: Duration = .seconds(3)
  private static let contactsRefreshIntervalSec: TimeInterval = 3600
  private static let scanIntervalSec: TimeInterval = 60
  static let defaultScanLimit = 20
  var state = AppState()
  var status = ""
  var keyStatus = ""
  var mailStatus = String(localized: "Mail connection not checked")
  var mailPermissionDenied = false
  var contactsStatus = String(localized: "Contacts optional — not requested")
  var busy = false
  var storageReady = false
  var hasLoadedState = false
  var accounts: [MailAccount] = []
  var showDigest = false
  var showCorrections = false
  var correctionResults: [MailCorrectionResult] = []
  var showJunk = false
  var junkMessages: [MailEnvelope] = []
  var junkTotal = 0
  var previewText = ""
  var showPreview = false
  var scanHealth: [String: MailScanHealth] = [:]
  private var monitoring: Task<Void, Never>?
  var store: Store?
  var pipeline: Pipeline?
  let adapter: AppleMailAdapter
  let preferences: UserDefaults
  let uiTesting: Bool
  private var work: Task<Void, Never>?
  var lastScan = Date.distantPast
  private var lastContactsRefresh = Date.distantPast
  private var settingsWork: Task<Void, Never>?
  private var pendingSettings = 0
  var today: [DecisionRecord] { state.records.filter { Calendar.current.isDateInToday($0.date) } }
  var monthCost: Double {
    state.costByMonth?[AppState.monthKey(.now)]
      ?? state.records.filter {
        Calendar.current.isDate($0.date, equalTo: .now, toGranularity: .month)
      }.reduce(0) { $0 + ($1.verdict?.usage.estimatedCost ?? 0) }
  }
  private var canMonitorMail: Bool {
    !uiTesting && !busy && state.settings.onboardingComplete
  }
  var contactsNeedRefresh: Bool {
    Date().timeIntervalSince(lastContactsRefresh) >= Self.contactsRefreshIntervalSec
  }
  var canScanAutomatically: Bool {
    state.settings.onboardingComplete && [.mailRule, .mailKit, .imap].contains(state.settings.route)
      && !state.settings.paused
  }
  init(preview: Bool = false) {
    hasLoadedState = preview
    uiTesting = preview || ProcessInfo.processInfo.arguments.contains("--ui-testing")
    if uiTesting {
      guard let isolated = UserDefaults(suiteName: "codes.tim.SpamWise.ui.\(UUID())") else {
        preconditionFailure("UI fixtures require an isolated preferences suite.")
      }
      preferences = isolated
    } else {
      preferences = .standard
    }
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
}

extension AppModel {
  func refresh() async {
    defer { hasLoadedState = true }
    guard let store else { return }
    do {
      var loaded = try await StateRepository.load(store)
      if pendingSettings > 0 { loaded.settings = state.settings }
      state = loaded
      scanHealth = try await MailHealthRepository.load(store)
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
  func startMonitoring() {
    guard monitoring == nil else { return }
    monitoring = Task { await monitor() }
  }
  func monitor() async {
    #if DEBUG
      if uiTesting, let store {
        do {
          try await UITestFixture.seed(arguments: ProcessInfo.processInfo.arguments, in: store)
        } catch {
          status = String(localized: "Correction fixture could not be loaded.")
        }
      }
    #endif
    await refresh()
    while !Task.isCancelled {
      try? await Task.sleep(for: Self.monitorInterval)
      guard !Task.isCancelled else { return }
      await refresh()
      if canMonitorMail {
        if contactsNeedRefresh { try? await refreshContacts() }
        if canScanAutomatically, Date().timeIntervalSince(lastScan) > Self.scanIntervalSec {
          scan(dryRun: state.settings.dryRun, automatic: true)
        }
      }
    }
  }
}

extension AppModel {
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
  }
  func togglePause() {
    setSetting(\.paused, to: !state.settings.paused)
  }
}

extension AppModel {
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
}

extension AppModel {
  func checkMail() {
    run { [self] in
      mailPermissionDenied = false
      do {
        if uiTesting { throw IntegrationError.permissionDenied }
        mailStatus = String(localized: "Waiting for Mail Automation permission…")
        try await SystemAppleEventRunner.requestMailPermission()
        try await discoverAccounts()
        mailStatus =
          String(
            localized:
              "Connected — \(accounts.count, format: .number) accounts readable. Actions need a disposable-message test."
          )
        status = String(localized: "Mail connection checked")
      } catch IntegrationError.permissionDenied {
        mailPermissionDenied = true
        mailStatus = Self.describe(IntegrationError.permissionDenied)
        throw IntegrationError.permissionDenied
      } catch {
        mailStatus = Self.describe(error)
        throw error
      }
    }
  }
  func requestContacts() {
    run { [self] in
      try await refreshContacts(requestAccess: true)
    }
  }
  func refreshContacts(requestAccess: Bool = false) async throws {
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
}

extension AppModel {
  func maintainHistory() async {
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
}

extension AppModel {
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
}

struct ScanBatch {
  let adapter: any MailClientAdapter
  let messages: [MailEnvelope]
  let retryAccountID: String?
}
