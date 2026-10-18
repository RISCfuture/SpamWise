public import Observation
import SwiftUI
import SpamWiseCore
import MailIntegration

/// The state and actions behind every SpamWise window, menu and App Intent.
@MainActor @Observable public final class AppModel {
  private static let monitorInterval: Duration = .seconds(3)
  private static let contactsRefreshIntervalSec: TimeInterval = 3600
  private static let scanIntervalSec: TimeInterval = 60
  static let defaultScanLimit = 20
  var state = AppState()
  var status = ""
  var keyStatus = ""
  var mailStatus = String(localized: "Mail connection not checked")
  var mailPermissionDenied = false
  var mailAutomation = MailAutomationStatus.unknown
  var moveTestStatus = ""
  var contactsStatus = String(localized: "Contacts optional — not requested")
  var busy = false
  var storageReady = false
  var hasLoadedState = false
  var accounts: [MailAccount] = []
  var showDigest = false
  var showCorpus = false
  var showAudit = false
  var showCorrections = false
  var correctionResults: [MailCorrectionResult] = []
  var showJunk = false
  var folders: [MailFolder] = []
  var junkMessages: [ReviewMessage] = []
  var junkTotal = 0
  var previewText = ""
  var showPreview = false
  var scanHealth: [String: MailScanHealth] = [:]
  var spending: MonthlySpending?
  var spendingToken: Int?
  var spendingLimitError: String?
  var historicalPreview: [String: [UUID]] = [:]
  private var inboxCheckPending = false
  var recoveryNeeded = false
  var changeTokens: [StateSlice: Int] = [:]
  var recordStamp = 0
  private var monitoring: Task<Void, Never>?
  var store: Store?
  var pipeline: Pipeline?
  let adapter: AppleMailAdapter
  let preferences: UserDefaults
  let uiTesting: Bool
  let notifications = LocalNotifications()
  private var work: Task<Void, Never>?
  var lastScan = Date.distantPast
  private var lastContactsRefresh = Date.distantPast
  private var settingsWork: Task<Void, Never>?
  var pendingSettings = 0
  var today: [DecisionRecord] { state.records.filter { Calendar.current.isDateInToday($0.date) } }
  var monthCost: Double { state.costByMonth[AppState.monthKey(.now), default: 0] }
  var spendingLimitReached: Bool {
    spending?.limitReached == true
      && [.claude, .openAI, .gemini].contains(state.settings.advancedOptions.backend)
  }
  private var canMonitorMail: Bool {
    !uiTesting && !busy && state.settings.onboardingComplete
  }
  var contactsNeedRefresh: Bool {
    Date().timeIntervalSince(lastContactsRefresh) >= Self.contactsRefreshIntervalSec
  }
  var filteringStatus: FilteringStatus {
    FilteringStatus(settings: state.settings, mailAutomation: mailAutomation)
  }
  var canScanAutomatically: Bool {
    filteringStatus.allowsAutomaticChecks
      && (state.settings.advancedOptions.transport == .imap || mailAutomation == .granted)
  }
  private var canReadMailAutomation: Bool {
    !uiTesting && state.settings.onboardingComplete
      && state.settings.advancedOptions.transport == .appleMail
  }
  init(preview: Bool = false) {
    hasLoadedState = preview
    uiTesting = preview || ProcessInfo.processInfo.arguments.contains("--ui-testing")
    if !uiTesting { notifications.configure() }
    if uiTesting {
      guard let isolated = UserDefaults(suiteName: "codes.tim.SpamWise.ui.\(UUID())") else {
        preconditionFailure("UI fixtures require an isolated preferences suite.")
      }
      preferences = isolated
    } else {
      preferences = .standard
    }
    #if DEBUG
      if uiTesting {
        accounts = [
          MailAccount(id: "ui-test", name: "Example account", addresses: ["me@example.org"])
        ]
      }
      if uiTesting, ProcessInfo.processInfo.arguments.contains("--ui-automation") {
        adapter = AppleMailAdapter(runner: SelectedFixtureAppleEventRunner())
      } else {
        adapter = AppleMailAdapter(
          runner: uiTesting ? DeniedAppleEventRunner() : SystemAppleEventRunner()
        )
      }
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
      #if DEBUG
        if uiTesting, ProcessInfo.processInfo.arguments.contains("--ui-automation") {
          pipeline = Pipeline(
            store: store,
            classifier: MockClassifier(
              verdict: .init(label: .junk, confidence: 99, reason: "Synthetic unwanted newsletter")
            )
          )
        }
      #endif
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
      if canReadMailAutomation {
        mailAutomation = await SystemAppleEventRunner.mailAutomationStatus()
      }
      if canMonitorMail {
        if state.settings.mailOptions.notifications.enabledSince != nil, let store {
          do { try await notifications.deliver(store: store) } catch {
            status = String(
              localized: "Notification delivery failed. Mail decisions are unchanged."
            )
          }
        }
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
    enqueueSettingsWrite { [self] in
      do { try await StateRepository.editSettings(store, edit) } catch {
        status = String(localized: "Settings could not be saved; mail stays unchanged.")
      }
      pendingSettings -= 1
    }
  }
  /// Runs `write` after every earlier settings write, then refreshes from shared storage.
  func enqueueSettingsWrite(_ write: @escaping @MainActor () async -> Void) {
    let previous = settingsWork
    settingsWork = Task {
      await previous?.value
      await write()
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
      if !$0.onboardingComplete { $0.dryRun = true }
      $0.onboardingComplete = true
    }
    let scope = state.settings.mailOptions.accountIDs
    startInboxFiltering(for: accounts.filter { scope?.contains($0.id) ?? true }, replacing: false)
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
      do { try await operation() } catch { status = Self.describe(error) }
      await refresh()
      busy = false
      if inboxCheckPending {
        inboxCheckPending = false
        requestInboxCheck()
      }
    }
  }
  /// Checks the newest Inbox mail now, or once the operation in progress finishes.
  func requestInboxCheck() {
    guard !busy else { inboxCheckPending = true; return }
    scan(dryRun: state.settings.dryRun, automatic: true)
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
        mailAutomation = .granted
        try await discoverAccounts()
        let validated = try await validateMailboxRoles()
        mailStatus =
          String(
            localized:
              "Connected — \(accounts.count, format: .number) accounts readable; Inbox and Junk mailboxes validated for \(validated, format: .number)."
          )
        status = String(localized: "Mail connection checked")
      } catch IntegrationError.permissionDenied {
        mailPermissionDenied = true
        mailAutomation = .notAuthorized
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
        try await StateRepository.update(store, loading: StateSlices([.contacts])) {
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
  /// Imports the newest bounded Inbox and Sent history of the selected transport.
  func importHistory() {
    run { [self] in
      guard let store else { throw IntegrationError.unavailable }
      let source: any MailSweepSource =
        state.settings.advancedOptions.transport == .imap
        ? try await configuredIMAPAdapter() : adapter
      try await HistoryMaintenance(source: source, store: store).importRecent()
      status = String(
        localized: "Imported bounded Inbox and Sent history; remaining history is unknown."
      )
    }
  }
}
