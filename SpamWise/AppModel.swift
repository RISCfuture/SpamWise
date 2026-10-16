import SwiftUI
import SpamWiseCore
import MailIntegration

@MainActor @Observable final class AppModel {
  var state = AppState()
  var status = "Ready for setup"
  var keyStatus = "Key not verified in this session"
  var mailStatus = "Mail connection not checked"
  var contactsStatus = "Contacts optional — not requested"
  var busy = false
  var storageReady = false
  var accounts: [MailAccount] = []
  var showSetup = false
  private var store: Store?
  private var pipeline: Pipeline?
  private let adapter: AppleMailAdapter
  private let uiTesting: Bool
  private var work: Task<Void, Never>?
  private var lastScan = Date.distantPast
  init(preview: Bool = false) {
    uiTesting = preview || ProcessInfo.processInfo.arguments.contains("--ui-testing")
    adapter = AppleMailAdapter(runner: SystemAppleEventRunner())
    do {
      let url =
        uiTesting
        ? FileManager.default.temporaryDirectory.appending(
          path: "SpamWise-UI-\(UUID())/state.store"
        ) : try Store.sharedURL()
      let store = try Store(url: url); self.store = store
      pipeline = Pipeline(
        store: store,
        classifier: ClaudeClassifier { try APIKeychain().read() },
        rdap: RDAPLookup(
          cacheURL: url.deletingLastPathComponent().appending(path: "rdap-cache.json")
        )
      )
      storageReady = true
    } catch {
      status =
        "Shared storage unavailable. Check signing and App Group access; mail stays unchanged."
    }
  }
  func refresh() async {
    guard let store else { return }
    do { state = try await StateRepository.load(store) } catch {
      status = "Shared storage unavailable; mail stays unchanged."
    }
  }
  func monitor() async {
    await refresh()
    while !Task.isCancelled {
      try? await Task.sleep(for: .seconds(3))
      guard !Task.isCancelled else { return }
      await refresh()
      if !uiTesting, !busy, state.settings.onboardingComplete, state.settings.route == .mailRule,
        !state.settings.paused, Date().timeIntervalSince(lastScan) > 60
      {
        scan(dryRun: state.settings.dryRun, automatic: true)
      }
    }
  }
  func saveSettings(_ settings: SpamWiseCore.Settings) {
    guard let store else { return }
    Task {
      do {
        try await StateRepository.update(store) { state in
          var settings = settings
          settings.correctionLimit = min(100, max(0, settings.correctionLimit))
          settings.bodyTokenBudget = min(4000, max(100, settings.bodyTokenBudget))
          if settings.validatedAccounts.isEmpty { settings.dryRun = true }
          state.settings = settings; state.revision += 1; state.retries.removeAll()
        }
        await refresh()
      } catch { status = "Settings could not be saved; mail stays unchanged." }
    }
  }
  func finishSetup() {
    var settings = state.settings; settings.onboardingComplete = true; settings.dryRun = true
    saveSettings(settings); showSetup = false
  }
  func togglePause() {
    var settings = state.settings; settings.paused.toggle(); saveSettings(settings)
  }
  func cancel() {
    work?.cancel()
    status = "Cancelling; mail stays unchanged unless an action was already requested."
  }
  private func run(_ operation: @escaping @MainActor () async throws -> Void) {
    guard !busy else { return }; busy = true
    work = Task {
      defer { busy = false }
      do { try await operation() } catch { status = Self.describe(error) }
      await refresh()
    }
  }
  func verifyKey(_ key: String) {
    let credential = key.trimmingCharacters(in: .whitespacesAndNewlines)
    run { [self] in
      guard !credential.isEmpty else { throw ClassificationError.missingCredential }
      keyStatus = "Verifying Haiku 5.5…"
      do {
        let raw = Data(
          """
          From: setup@example.org
          Subject: API connection check

          Hello. This is a synthetic SpamWise connection test.
          """
          .utf8
        )
        let message = try MIMEParser().parse(raw)
        let verdict = try await ClaudeClassifier(key: { credential }).classify(
          .init(message: message, evidence: .init(message: message))
        )
        try APIKeychain().save(credential)
        if let store {
          let record = DecisionRecord(
            identity: .init(accountID: nil, contentHash: message.hash),
            sender: "SpamWise setup",
            subject: "API connection verification",
            verdict: verdict,
            decision: .init(label: .inbox, action: .none, reason: "Haiku 5.5 connection verified"),
            outcome: .noAction,
            path: "verification"
          )
          try await StateRepository.update(store) { $0.record(record) }
        }
        keyStatus = "Verified — stored in Keychain"; status = "Haiku 5.5 is ready"
      } catch { keyStatus = Self.describe(error); throw error }
    }
  }
  func checkMail() {
    run { [self] in
      do {
        if uiTesting { throw IntegrationError.permissionDenied }
        accounts = try await adapter.accounts()
        mailStatus =
          "Connected — \(accounts.count) accounts readable. Actions need a disposable-message test."
        status = "Mail connection checked"
      } catch { mailStatus = Self.describe(error); throw error }
    }
  }
  func requestContacts() {
    run { [self] in
      let addresses = try await ContactsLookup().addresses(requestAccess: true)
      if let store {
        try await StateRepository.update(store) {
          $0.contactAddresses = addresses; $0.contactsUpdatedAt = .now
        }
      }
      contactsStatus =
        addresses == nil
        ? "Contacts access denied — relationship remains unknown" : "Contacts connected"
    }
  }
  func importHistory() {
    run { [self] in
      let histories = try await adapter.importHistory(previous: state.histories)
      if let store {
        try await StateRepository.update(store) { state in
          for (account, imported) in histories { state.histories[account] = imported }
        }
      }
      status = "Imported bounded Inbox and Sent history; remaining history is unknown."
    }
  }
  func testDisposableMessage() {
    run { [self] in
      let account = try await adapter.testDisposableMessage()
      if let store {
        try await StateRepository.update(store) { state in
          state.settings.validatedAccounts.insert(account); state.settings.route = .mailRule
          state.revision += 1
        }
      }
      mailStatus = "Action test passed for one account — dry run remains on."
      status = mailStatus
    }
  }
  func scan(dryRun: Bool = true, automatic: Bool = false, limit: Int = 20) {
    guard let pipeline else { return }
    if automatic
      && (!state.settings.onboardingComplete || state.settings.route != .mailRule
        || state.settings.paused)
    {
      return
    }
    run { [self] in
      lastScan = .now
      let messages = try await adapter.recentMessages(limit: limit)
      let seen = Set(state.records.map { $0.identity.key })
      var count = 0
      for message in messages where !automatic || !seen.contains(message.identity.key) {
        try Task.checkCancellation()
        _ = await pipeline.process(message, adapter: adapter, forceDryRun: dryRun)
        count += 1; status = "Classified \(count) of \(messages.count) messages"
        await refresh()
      }
      if !dryRun { await pipeline.retryDue(adapter: adapter) }
      status = dryRun ? "Dry run finished — no mail actions requested" : "Mail check finished"
    }
  }
  func correct(_ record: DecisionRecord, label: MailLabel, scope: RuleScope = .address) {
    guard let pipeline else { return }
    run { [self] in
      let result = try await pipeline.correct(
        recordID: record.id,
        label: label,
        scope: scope,
        adapter: adapter
      )
      status =
        "Correction saved. Mail action: \(result.outcome.rawValue)."
        + (result.actionError.map { " " + $0 } ?? "")
    }
  }
  func handle(_ url: URL) {
    guard url.scheme == "spamwise", url.host == "check-inbox" else { return }
    scan(dryRun: state.settings.dryRun, automatic: true)
  }
  func revealRule() {
    guard let url = Bundle.main.url(forResource: "SpamWiseRule", withExtension: "scpt") else {
      status = "Rule script missing from app bundle"; return
    }
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }
  static func describe(_ error: any Error) -> String {
    if error as? IntegrationError == .permissionDenied {
      return
        "Automation permission denied. Allow SpamWise in System Settings → Privacy & Security → Automation."
    }
    if let error = error as? IntegrationError { return error.localizedDescription }
    if let error = error as? ClassificationError { return error.localizedDescription }
    if error is KeychainError {
      return "Keychain unavailable. Check the signed app’s shared Keychain entitlement."
    }
    if error is CancellationError { return "Cancelled — no further actions requested." }
    return "Operation unavailable. Mail stays unchanged; check Help for troubleshooting."
  }
  var today: [DecisionRecord] { state.records.filter { Calendar.current.isDateInToday($0.date) } }
  var monthCost: Double {
    state.costByMonth?[AppState.monthKey(.now)]
      ?? state.records.filter {
        Calendar.current.isDate($0.date, equalTo: .now, toGranularity: .month)
      }.reduce(0) { $0 + ($1.verdict?.usage.estimatedCost ?? 0) }
  }
}
