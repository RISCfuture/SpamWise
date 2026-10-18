import Foundation
import SpamWiseCore
import MailIntegration

extension AppModel {
  static func unreadableStatus(_ count: Int) -> String {
    String(localized: "Unreadable messages: \(count, format: .number)")
  }
  func scan(dryRun: Bool = true, automatic: Bool = false, limit: Int = AppModel.defaultScanLimit) {
    guard let pipeline, !automatic || canScanAutomatically else { return }
    run { [self] in
      await prepareScan(automatic: automatic)
      if automatic, state.settings.advancedOptions.transport == .appleMail {
        try await scanMailAccounts(with: pipeline, dryRun: dryRun, limit: limit)
        return
      }
      let batch = try await scanBatch(automatic: automatic, limit: limit)
      try await classify(batch, with: pipeline, dryRun: dryRun, automatic: automatic)
      if !dryRun {
        await pipeline.retryDue(adapter: batch.adapter, accountID: batch.retryAccountID)
      }
      status =
        dryRun
        ? String(localized: "Dry run finished — no mail actions requested")
        : String(localized: "Mail check finished")
      if batch.unavailableCount > 0 { status = Self.unreadableStatus(batch.unavailableCount) }
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
  private func scanMailAccounts(with pipeline: Pipeline, dryRun: Bool, limit: Int) async throws {
    guard let store else { throw IntegrationError.unavailable }
    try await discoverAccounts()
    for account in accounts
    where state.settings.mailOptions.accountIDs?.contains(account.id) ?? true {
      try Task.checkCancellation()
      guard !state.settings.paused else { return }
      do {
        try await AppleMailInboxSweep(adapter: adapter, pipeline: pipeline, store: store).run(
          account: account,
          dryRun: dryRun,
          limit: limit
        ) { count, total in await self.showProgress(count, of: total) }
        if !dryRun { await pipeline.retryDue(adapter: adapter, accountID: account.id) }
      } catch is CancellationError { throw CancellationError() } catch {
        let description = Self.describe(error)
        try await MailHealthRepository.update(store, accountID: account.id, name: account.name) {
          $0.failure = description
        }
      }
      await refresh()
    }
    try await scanConfiguredFolders(with: pipeline, dryRun: dryRun, limit: limit)
    status = String(localized: "Mail sweep updated. See Accounts for scan health.")
  }
  private func prepareScan(automatic: Bool) async {
    lastScan = .now
    if !uiTesting, contactsNeedRefresh { try? await refreshContacts() }
    if automatic { await maintainHistory() }
    await refresh()
  }
  private func scanBatch(automatic: Bool, limit: Int) async throws -> ScanBatch {
    if state.settings.advancedOptions.transport == .imap {
      let imap = try await configuredIMAPAdapter()
      guard automatic else {
        let messages = try await imap.recentMessages(limit: limit)
        return ScanBatch(adapter: imap, messages: messages, retryAccountID: imap.accountID)
      }
      let sweep = try await imap.nextInboxSweep(limit: limit, cursorStore: store)
      return ScanBatch(adapter: imap, messages: sweep.messages, retryAccountID: imap.accountID) {
        [store] in try await imap.commit(sweep, cursorStore: store)
      }
    }
    try await discoverAccounts()
    var messages: [MailEnvelope] = [], unavailableCount = 0
    for account in accounts
    where state.settings.mailOptions.accountIDs?.contains(account.id) ?? true {
      try Task.checkCancellation()
      let page = try await adapter.inboxPage(accountID: account.id, offset: 0, limit: limit)
      messages += page.messages
      unavailableCount += page.unavailableCount
    }
    return ScanBatch(
      unavailableCount: unavailableCount,
      adapter: adapter,
      messages: messages,
      retryAccountID: nil
    )
  }
  @discardableResult func classify(
    _ batch: ScanBatch,
    with pipeline: Pipeline,
    dryRun: Bool,
    automatic: Bool
  ) async throws -> [DecisionRecord] {
    let total = batch.messages.count
    return try await pipeline.processBatch(
      batch.messages,
      adapter: batch.adapter,
      dryRun: dryRun,
      skipsSettled: automatic,
      progress: { count in await self.showProgress(count, of: total) },
      onCompletion: batch.commit
    )
  }
  private func showProgress(_ count: Int, of total: Int) async {
    status = String(
      localized: "Classified \(count, format: .number) of \(total, format: .number) messages"
    )
    await refresh()
  }
}
