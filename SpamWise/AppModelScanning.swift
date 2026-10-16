import Foundation
import SpamWiseCore
import MailIntegration

extension AppModel {
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
    }
  }
  func discoverAccounts() async throws {
    let discovered = try await adapter.accounts()
    accounts = discovered
    if let store {
      let addresses = Set(discovered.flatMap(\.addresses))
      try await StateRepository.update(store) { $0.ownAddresses = addresses }
    }
  }
  private func scanMailAccounts(with pipeline: Pipeline, dryRun: Bool, limit: Int) async throws {
    guard let store else { throw IntegrationError.unavailable }
    try await discoverAccounts()
    for account in accounts
    where state.settings.mailOptions.accountIDs?.contains(account.id) ?? true {
      try Task.checkCancellation()
      guard !state.settings.paused else { return }
      try await MailHealthRepository.update(store, accountID: account.id, name: account.name) {
        $0.lastAttempt = .now
      }
      do {
        let offset = try await MailHealthRepository.load(store)[account.id]?.nextOffset ?? 0
        let page = try await adapter.inboxPage(accountID: account.id, offset: offset, limit: limit)
        try await classify(
          ScanBatch(adapter: adapter, messages: page.messages, retryAccountID: account.id),
          with: pipeline,
          dryRun: dryRun,
          automatic: true
        )
        try Task.checkCancellation()
        try await MailHealthRepository.update(store, accountID: account.id, name: account.name) {
          $0.complete(count: page.messages.count, total: page.total)
        }
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
      let messages =
        try await automatic
        ? imap.nextInboxMessages(limit: limit, cursorStore: store)
        : imap.recentMessages(limit: limit)
      return ScanBatch(adapter: imap, messages: messages, retryAccountID: imap.accountID)
    }
    try await discoverAccounts()
    var messages: [MailEnvelope] = []
    for account in accounts
    where state.settings.mailOptions.accountIDs?.contains(account.id) ?? true {
      try Task.checkCancellation()
      messages += try await adapter.inboxPage(accountID: account.id, offset: 0, limit: limit)
        .messages
    }
    return ScanBatch(adapter: adapter, messages: messages, retryAccountID: nil)
  }
  func classify(
    _ batch: ScanBatch,
    with pipeline: Pipeline,
    dryRun: Bool,
    automatic: Bool
  ) async throws {
    let seen = Set(
      state.records.filter {
        $0.outcome != .paused && $0.outcome != .superseded
          && (dryRun || $0.outcome != .dryRun)
          && ($0.verdict != nil || $0.correctedLabel != nil || $0.revision == state.revision)
      }.map { $0.identity.key }
    )
    var count: UInt = 0
    for message in batch.messages where !automatic || !seen.contains(message.identity.key) {
      try Task.checkCancellation()
      if automatic, state.settings.paused { throw CancellationError() }
      let record = await pipeline.process(message, adapter: batch.adapter, forceDryRun: dryRun)
      if let store {
        let saved = try await StateRepository.load(store)
        guard saved.records.contains(where: { $0.id == record.id }) else {
          throw IntegrationError.unavailable
        }
      }
      count += 1
      status = String(
        localized:
          "Classified \(count, format: .number) of \(batch.messages.count, format: .number) messages"
      )
      await refresh()
    }
  }
}
