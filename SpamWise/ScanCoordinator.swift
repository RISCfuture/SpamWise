import Foundation
import Network
import Observation
import SpamWiseCore
import MailIntegration

/**
 Background mail checking, separate from the user's own operations.

 Automatic sweeps run in their own task, a minute after the previous sweep finished. A check
 requested while one runs follows it instead of being dropped. The pipeline and adapters are
 actors, so corrections and other user work interleave safely with a sweep.
 */
@MainActor
@Observable
final class ScanCoordinator {
  /// Messages read per page by sweeps and previews.
  static let pageLimit = 20
  /// The pause between the end of one automatic check and the start of the next.
  static let interval: Duration = .seconds(60)
  /// Zero-based pages of older or folder mail that a preview can reach.
  static let previewPages = 0...1000
  private static let sweepReason = "Checking mail"
  /// ``interval`` as the user reads it, such as “1 minute”.
  static var intervalText: String {
    interval.formatted(.units(allowed: [.minutes, .seconds], width: .wide))
  }
  /// Progress of the sweep in progress, or nil when none is running.
  private(set) var progress: ScanProgress?
  /// The latest sweep's problems, or nil when it finished cleanly.
  private(set) var sweepStatus: OperationStatus?
  /// When the latest sweep finished.
  private(set) var lastCompletion: Date?
  /// Whether the latest sweep failed outright or could not check some account or folder.
  private(set) var lastSweepFailed = false
  /// Whether the network is reachable, as last reported by the system.
  private(set) var isOnline = true
  /// The user's dry run of recent Inbox mail.
  let preview = TrackedOperation()
  /// The latest finished dry run of recent Inbox mail, or nil while one runs or after it failed.
  private(set) var lastPreview: MailPreview?
  @ObservationIgnored private let services: AppServices
  @ObservationIgnored private let shared: SharedStateModel
  @ObservationIgnored private let mail: MailConnectionModel
  @ObservationIgnored private let relationships: RelationshipsModel
  @ObservationIgnored private let runner = CoalescingRunner()
  @ObservationIgnored private var lastFinished: ContinuousClock.Instant?
  @ObservationIgnored private var historyUnavailable = false

  var filteringStatus: FilteringStatus {
    FilteringStatus(settings: shared.settings, mailAutomation: mail.automation)
  }
  /// The state the menu bar and Activity footer report, most limiting first.
  var filteringState: FilteringState {
    FilteringState(
      filteringStatus,
      needsNetwork: shared.settings.checksNeedNetwork,
      isOnline: isOnline,
      isFailing: lastSweepFailed || hasStalledAccount
    )
  }
  /// Whether an account in scope keeps timing out on the same page.
  private var hasStalledAccount: Bool {
    let scope = shared.settings.mailOptions.accountIDs
    return shared.knownAccounts.contains { account in
      (scope?.contains(account.id) ?? true) && shared.scanHealth[account.id]?.isStalled == true
    }
  }
  var canScanAutomatically: Bool {
    filteringStatus.allowsAutomaticChecks
      && (shared.settings.advancedOptions.transport == .imap || mail.automation == .granted)
  }
  private var isDue: Bool {
    lastFinished.map { .now - $0 >= Self.interval } ?? true
  }

  init(
    services: AppServices,
    shared: SharedStateModel,
    mail: MailConnectionModel,
    relationships: RelationshipsModel
  ) {
    self.services = services
    self.shared = shared
    self.mail = mail
    self.relationships = relationships
  }

  static func unreadableStatus(_ count: Int) -> String {
    String(localized: "Unreadable messages: \(count)")
  }

  /// Follows network reachability until cancelled.
  func monitorNetwork() async {
    for await path in NWPathMonitor() { isOnline = path.status == .satisfied }
  }

  /// Starts a sweep when automatic checks are allowed and the interval has passed.
  func scanIfDue() {
    guard canScanAutomatically, progress == nil, isDue else { return }
    runner.request { [self] in await BackgroundActivity.run(Self.sweepReason) { await sweep() } }
  }

  /// Checks the newest Inbox mail now, or right after the sweep in progress.
  func requestInboxCheck() {
    guard canScanAutomatically else { return }
    runner.request { [self] in await BackgroundActivity.run(Self.sweepReason) { await sweep() } }
  }

  /// Stops the sweep in progress; the next one starts at the usual interval.
  func stop() { runner.cancel() }

  /**
   Previews the newest `limit` Inbox messages across all accounts in scope as a dry run.

   Messages previewed before with unchanged content and policy keep their decision, so a repeated
   preview makes no new provider requests.
   */
  func previewRecent(limit: Int = ScanCoordinator.pageLimit) {
    preview.run { [self] in
      lastPreview = nil
      await prepare()
      let sweeper = try await services.sweeper(transport: shared.settings.advancedOptions.transport)
      let result = try await sweeper.previewRecent(total: limit) { [shared] _ in
        await shared.refresh()
      }
      lastPreview = result
      return result.unavailableCount > 0
        ? Self.unreadableStatus(result.unavailableCount)
        : String(localized: "Dry run finished — no mail actions requested")
    }
  }

  /// Records now as the Inbox start boundary for the accounts, keeping existing boundaries unless `replacing`.
  func startInboxFiltering(for accounts: [MailAccount], replacing: Bool) {
    guard let store = services.store, !accounts.isEmpty else { return }
    let now = Date.now
    Task { [shared] in
      for account in accounts {
        try? await MailHealthRepository.update(store, accountID: account.id, name: account.name) {
          if replacing || $0.inboxStart == nil { $0.inboxStart = now }
        }
      }
      await shared.refresh()
    }
  }

  private func sweep() async {
    guard canScanAutomatically else { return }
    progress = ScanProgress()
    historyUnavailable = false
    do {
      await prepare()
      let settings = shared.settings
      let sweeper = try await services.sweeper(transport: settings.advancedOptions.transport)
      let summary = try await sweeper.sweep(dryRun: settings.dryRun, limit: Self.pageLimit) {
        await self.handle($0)
      }
      sweepStatus = status(after: summary)
      lastSweepFailed = summary.failures > 0
    } catch is CancellationError {
      sweepStatus = .message(
        String(localized: "Mail check stopped. The next check starts in \(Self.intervalText).")
      )
    } catch {
      sweepStatus = .failure(OperationFailure(error))
      lastSweepFailed = true
    }
    progress = nil
    lastFinished = .now
    lastCompletion = .now
    await shared.refresh()
  }

  private func prepare() async {
    await relationships.refreshContactsIfDue()
    if shared.settings.advancedOptions.transport == .appleMail {
      try? await mail.discoverAccounts()
    }
    await shared.refresh()
  }

  private func handle(_ event: MailSweepEvent) async {
    switch event {
      case let .processed(count, total):
        progress = ScanProgress(processed: count, total: total)
      case .historyUnavailable:
        historyUnavailable = true
      case .accountSwept, .accountFailed, .folderSwept, .folderFailed: break
    }
    await shared.refresh()
  }

  private func status(after summary: MailSweepSummary) -> OperationStatus? {
    if summary.failures > 0 {
      return .failure(
        OperationFailure(
          message: String(
            localized:
              "Some accounts or folders couldn’t be checked. See their status in Settings → Accounts."
          )
        )
      )
    }
    guard historyUnavailable else { return nil }
    return .message(
      String(
        localized: "History refresh unavailable — only previously stored relationships are known"
      )
    )
  }
}

/// How far the sweep in progress has read its current page.
struct ScanProgress: Equatable {
  /// Messages processed on the current page.
  var processed = 0
  /// Messages on the current page; zero before the first page is read.
  var total = 0
}
