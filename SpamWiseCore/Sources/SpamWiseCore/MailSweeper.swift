import Foundation
import Synchronization

/// Which accounts and folders an automatic sweep covers.
public struct MailSweepScope: Sendable {
  /// The configured Mail.app scope: selected accounts and their enabled folder plans.
  public static let configured = Self(accounts: .configured, includesFolders: true)
  /// Every account of a dedicated source, such as one IMAP connection, without folder plans.
  public static let allAccounts = Self(accounts: .all, includesFolders: false)
  /// How accounts are selected.
  public var accounts: Accounts
  /// Whether enabled folder plans are swept after the Inbox.
  public var includesFolders: Bool
  /// Creates a scope.
  public init(accounts: Accounts, includesFolders: Bool) {
    self.accounts = accounts; self.includesFolders = includesFolders
  }
  /// How accounts are selected.
  public enum Accounts: Sendable {
    /// The accounts selected in settings, or every account when none is selected.
    case configured
    /// Every account the source reports, regardless of the settings selection.
    case all
  }
}

/// Progress and health reported while a sweep runs.
public enum MailSweepEvent: Sendable {
  /// A page's messages were processed: the running count and the page size.
  case processed(count: Int, total: Int)
  /// An account's Inbox pass finished and its health was saved.
  case accountSwept(MailAccount)
  /// An account's Inbox pass failed; the failure is saved in its health.
  case accountFailed(MailAccount, any Error)
  /// A folder plan's page was handled and its health was saved.
  case folderSwept(MailFolderPlan)
  /// A folder plan's page failed; the failure is saved in its health.
  case folderFailed(MailFolderPlan, any Error)
  /// Relationship history could not be updated; only stored history is known.
  case historyUnavailable(any Error)
}

/// What one sweep did.
public struct MailSweepSummary: Sendable, Equatable {
  /// Accounts whose Inbox pass finished.
  public var sweptAccounts = 0
  /// Accounts and folders whose pass failed.
  public var failures = 0
  /// Whether the sweep stopped because filtering is paused.
  public var paused = false
  /// Creates an empty summary.
  public init() {}
}

/**
 Automatic mail discovery shared by the app and the headless daemon.

 A sweep maintains Sent history on its own schedule, then runs one Inbox pass per account in
 scope, then one page of each enabled folder plan. It decides which messages are new with the
 processed-message index (see ``ProcessedMessage/isSettled(revision:now:)``), saves each pass's
 cursor, coverage and failures in ``MailScanHealth``, requests due retries after live passes and
 observes training folders. A failing account or folder is recorded and the sweep continues;
 cancellation always ends it.
 */
public actor MailSweeper {
  /// Receives sweep events.
  public typealias EventHandler = @Sendable (MailSweepEvent) async -> Void
  /// Turns a failure into the sanitized text saved in scan health.
  public typealias FailureDescription = @Sendable (any Error) -> String

  let source: any MailSweepSource
  let store: Store
  let pipeline: Pipeline
  let scope: MailSweepScope
  let describe: FailureDescription
  /// Coverage of the pass in progress.
  var coverage = SweepCoverage()

  /**
   Creates a sweeper.

   - Parameters:
     - source: The client whose mailboxes are read and acted on.
     - store: Durable state shared with the pipeline.
     - pipeline: Classifies, persists and dispatches each message.
     - scope: The accounts and folders a sweep covers.
     - describe: Sanitizes failures for scan health.
   */
  public init(
    source: any MailSweepSource,
    store: Store,
    pipeline: Pipeline,
    scope: MailSweepScope = .configured,
    describe: @escaping FailureDescription = MailSweeper.describe
  ) {
    self.source = source; self.store = store; self.pipeline = pipeline; self.scope = scope
    self.describe = describe
  }

  /// The error's localized description, reason and recovery suggestion, which carry no secrets.
  public static func describe(_ error: any Error) -> String {
    guard let error = error as? any LocalizedError else {
      return String(localized: "The mail operation failed. Mail stays unchanged.", bundle: .module)
    }
    return [error.errorDescription, error.failureReason, error.recoverySuggestion]
      .compactMap(\.self).filter { !$0.isEmpty }.joined(separator: " ")
  }

  /// Health key of a folder plan, separate from account keys.
  public static func healthKey(for plan: MailFolderPlan) -> String { "folder:" + plan.id }

  /// Rethrows `error` as cancellation when it is one or the task was cancelled.
  static func rethrowCancellation(_ error: any Error) throws {
    if error is CancellationError || Task.isCancelled { throw CancellationError() }
  }

  /**
   Runs one automatic sweep.

   - Parameters:
     - dryRun: Whether to suppress mail actions regardless of settings.
     - limit: Maximum messages per page.
     - onEvent: Receives progress and health events.
   - Throws: Cancellation, or a failure reading the source's accounts or the store.
   */
  @discardableResult
  public func sweep(
    dryRun: Bool,
    limit: Int,
    onEvent: @escaping EventHandler = { _ in }
  ) async throws -> MailSweepSummary {
    var summary = MailSweepSummary()
    let settings = try await currentSettings()
    guard !settings.paused else { summary.paused = true; return summary }
    let accounts = try await accountsInScope(settings)
    await maintainHistory(of: accounts, onEvent: onEvent)
    for account in accounts {
      try Task.checkCancellation()
      guard try await !currentSettings().paused else { summary.paused = true; return summary }
      if try await sweepAccount(account, dryRun: dryRun, limit: limit, onEvent: onEvent) {
        summary.sweptAccounts += 1
      } else {
        summary.failures += 1
      }
    }
    guard scope.includesFolders else { return summary }
    summary.failures += try await sweepFolders(dryRun: dryRun, limit: limit, onEvent: onEvent)
    return summary
  }

  func currentSettings() async throws -> Settings {
    try await StateRepository.load(store, StateSlices()).settings
  }

  /// The source's accounts, limited to the settings selection under a configured scope.
  func accountsInScope(_ settings: Settings) async throws -> [MailAccount] {
    let accounts = try await source.sweepAccounts()
    guard scope.accounts == .configured, let selected = settings.mailOptions.accountIDs else {
      return accounts
    }
    return accounts.filter { selected.contains($0.id) }
  }

  /// Runs one account's pass, recording any failure in its health; returns whether it finished.
  private func sweepAccount(
    _ account: MailAccount,
    dryRun: Bool,
    limit: Int,
    onEvent: @escaping EventHandler
  ) async throws -> Bool {
    do {
      try await sweepInbox(of: account, dryRun: dryRun, limit: limit, onEvent: onEvent)
      if !dryRun { await pipeline.retryDue(adapter: source, accountID: account.id) }
      await onEvent(.accountSwept(account))
      return true
    } catch {
      try Self.rethrowCancellation(error)
      let description = describe(error)
      try await MailHealthRepository.update(store, accountID: account.id, name: account.name) {
        $0.recordFailure(description)
      }
      await onEvent(.accountFailed(account, error))
      return false
    }
  }

  /// Processes new Inbox mail, then backfill pages, and saves the pass's cursor and coverage.
  private func sweepInbox(
    of account: MailAccount,
    dryRun: Bool,
    limit: Int,
    onEvent: @escaping EventHandler
  ) async throws {
    let health = try await MailHealthRepository.load(store, key: account.id)
    let request = InboxPassRequest(
      start: health?.inboxStart ?? .now,
      resumeOffset: health?.nextOffset ?? 0,
      pageLimit: health?.pageLimit(for: limit) ?? limit
    )
    try await MailHealthRepository.update(store, accountID: account.id, name: account.name) {
      $0.inboxStart = request.start; $0.lastAttempt = .now
    }
    coverage = SweepCoverage()
    let traversal = try await source.sweepInbox(of: account, request) { page in
      try await self.process(page, accountID: account.id, dryRun: dryRun, onEvent: onEvent)
    }
    try Task.checkCancellation()
    guard !traversal.interrupted else { return }
    try await savePass(traversal, key: account.id, name: account.name)
  }

  private func savePass(_ traversal: InboxTraversal, key: String, name: String) async throws {
    let coverage = coverage
    let stall = traversal.stalledOffset.map { _ in describe(IntegrationError.timedOut) }
    try await MailHealthRepository.update(store, accountID: key, name: name) { health in
      if let stall {
        health.recordStall(traversal, coverage: coverage, failure: stall)
      } else {
        health.completePass(traversal, coverage: coverage)
      }
    }
  }

  /**
   Processes a discovered page, counts its coverage and ingests its eligible Inbox history.

   Mail returned from Junk is corrected first on live passes.
   */
  func process(
    _ page: MailPage,
    accountID: String,
    dryRun: Bool,
    ingestsHistory: Bool = true,
    onEvent: @escaping EventHandler
  ) async throws -> ProcessedPage {
    if !dryRun { _ = await pipeline.correctMailReturnedFromJunk(page.messages, adapter: source) }
    let completion = CompletionFlag(), total = page.messages.count
    let records = try await pipeline.processBatch(
      page.messages,
      adapter: source,
      dryRun: dryRun,
      skipsSettled: true,
      progress: { count in await onEvent(.processed(count: count, total: total)) },
      onCompletion: { completion.mark() }
    )
    try await countCoverage(of: page)
    if ingestsHistory { try await ingestHistory(page.messages, accountID: accountID, onEvent) }
    return ProcessedPage(records: records, completed: completion.isMarked)
  }

  private func countCoverage(of page: MailPage) async throws {
    let results = try await ProcessedMessageRepository.entries(
      for: page.messages.map(\.identity.key),
      in: store
    )
    for envelope in page.messages { coverage.count(results[envelope.identity.key]) }
    coverage.unclassified += page.unavailableCount
  }

  private func ingestHistory(
    _ envelopes: [MailEnvelope],
    accountID: String,
    _ onEvent: EventHandler
  ) async throws {
    do {
      let eligible = try await StateRepository.historyEligibleInbox(store, among: envelopes)
      guard !eligible.isEmpty else { return }
      try await HistoryRepository.ingest(
        accountID: accountID,
        sent: [],
        inbox: envelopes,
        eligible: eligible,
        trustedAuthServers: try await AuthenticationTrust.trustedServers(store)[accountID] ?? [],
        in: store
      )
    } catch {
      try Self.rethrowCancellation(error)
      await onEvent(.historyUnavailable(error))
    }
  }

  private func maintainHistory(of accounts: [MailAccount], onEvent: EventHandler) async {
    do {
      try await HistoryMaintenance(source: source, store: store).runIfDue(for: accounts)
    } catch {
      guard !Task.isCancelled else { return }
      await onEvent(.historyUnavailable(error))
    }
  }
}

/// Records, across concurrency domains, that a batch reached its completion callback.
final class CompletionFlag: Sendable {
  private let marked = Mutex(false)
  /// Whether ``mark()`` was called.
  var isMarked: Bool { marked.withLock { $0 } }
  /// Records completion.
  func mark() { marked.withLock { $0 = true } }
}
