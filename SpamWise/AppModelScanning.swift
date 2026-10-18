import Foundation
import SpamWiseCore
import MailIntegration

extension AppModel {
  static func unreadableStatus(_ count: Int) -> String {
    String(localized: "Unreadable messages: \(count, format: .number)")
  }
  private static func previewStatus(_ preview: MailPreview) -> String {
    preview.unavailableCount > 0
      ? unreadableStatus(preview.unavailableCount)
      : String(localized: "Dry run finished — no mail actions requested")
  }
  /// Sweeps mail automatically, or previews the newest `limit` Inbox messages across accounts.
  func scan(dryRun: Bool = true, automatic: Bool = false, limit: Int = AppModel.defaultScanLimit) {
    guard pipeline != nil, !automatic || canScanAutomatically else { return }
    run { [self] in
      await prepareScan()
      let sweeper = try await mailSweeper()
      guard automatic else {
        let preview = try await sweeper.previewRecent(total: limit) { await self.handle($0) }
        status = Self.previewStatus(preview)
        return
      }
      try await sweeper.sweep(dryRun: dryRun, limit: limit) { await self.handle($0) }
      status = String(localized: "Mail sweep updated. See Accounts for scan health.")
    }
  }
  func discoverAccounts() async throws {
    let discovered = try await adapter.accounts()
    accounts = discovered
    if let store {
      let addresses = Set(discovered.flatMap(\.addresses))
      try await StateRepository.update(store, loading: StateSlices([.contacts])) {
        $0.ownAddresses = addresses
      }
    }
  }
  /// Records now as the Inbox start boundary for the accounts, keeping existing boundaries unless `replacing`.
  func startInboxFiltering(for accounts: [MailAccount], replacing: Bool) {
    guard let store, !accounts.isEmpty else { return }
    let now = Date.now
    Task {
      for account in accounts {
        try? await MailHealthRepository.update(store, accountID: account.id, name: account.name) {
          if replacing || $0.inboxStart == nil { $0.inboxStart = now }
        }
      }
      await refresh()
    }
  }
  /// A sweeper over the selected transport, or over `source` when given.
  func mailSweeper(source: (any MailSweepSource)? = nil) async throws -> MailSweeper {
    guard let store, let pipeline else { throw IntegrationError.unavailable }
    let imap = source == nil && state.settings.advancedOptions.transport == .imap
    let selected: any MailSweepSource
    if let source {
      selected = source
    } else if imap {
      selected = try await configuredIMAPAdapter()
    } else {
      selected = adapter
    }
    return MailSweeper(
      source: selected,
      store: store,
      pipeline: pipeline,
      scope: imap ? .allAccounts : .configured,
      describe: { Self.describe($0) }
    )
  }
  /// Previews messages as a dry run, reusing unchanged earlier previews.
  func preview(_ messages: [MailEnvelope]) async throws -> [DecisionRecord] {
    try await mailSweeper(source: adapter).preview(messages) { await self.handle($0) }
  }
  private func prepareScan() async {
    lastScan = .now
    if !uiTesting, contactsNeedRefresh { try? await refreshContacts() }
    if state.settings.advancedOptions.transport == .appleMail { try? await discoverAccounts() }
    await refresh()
  }
  private func handle(_ event: MailSweepEvent) async {
    switch event {
      case .processed(let count, let total):
        status = String(
          localized: "Classified \(count, format: .number) of \(total, format: .number) messages"
        )
      case .historyUnavailable:
        mailStatus = String(
          localized: "History refresh unavailable — only previously stored relationships are known"
        )
      case .accountSwept, .accountFailed, .folderSwept, .folderFailed: break
    }
    await refresh()
  }
}
