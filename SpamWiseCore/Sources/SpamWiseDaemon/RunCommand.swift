import ArgumentParser
import Foundation
import MailIntegration
import SpamWiseCore
import Synchronization

/// Sweeps the configured Inbox once or on an interval.
struct RunCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "run",
    abstract: "Sweep the Inbox once, or repeatedly with --poll-seconds.",
    discussion: """
      Actions also require daemon validation of this exact endpoint and dry run disabled in the \
      store's settings. In poll mode a failed sweep is logged with its category and retried after \
      a growing delay; the daemon exits only on configuration errors or after repeated \
      authentication failures.
      """
  )
  private static let allowedPollSeconds = 60...3600
  private static let allowedPageSize = 1...100
  private static let maximumAuthenticationFailures = 3
  private static let maximumBackoffSec = 3600

  @OptionGroup var options: ConfigurationOptions

  @Flag(help: "Run one sweep and exit (the default without --poll-seconds).")
  var once = false

  @Option(name: .customLong("poll-seconds"), help: "Seconds between sweeps, 60 to 3600.")
  var pollSeconds: Int?

  @Option(help: "Messages per page, 1 to 100.")
  var limit = 20

  @Flag(help: "Request mail actions, subject to validation and the store's dry-run setting.")
  var actions = false

  @Option(
    help: ArgumentHelp(
      "Select a supported model in this daemon's own store; requires statePath.",
      valueName: "model"
    )
  )
  var model: ModelIdentifier?

  func validate() throws {
    if once, pollSeconds != nil { throw DaemonUsageError.onceWithPolling }
    if let pollSeconds, !Self.allowedPollSeconds.contains(pollSeconds) {
      throw DaemonUsageError.pollInterval(Self.allowedPollSeconds)
    }
    guard Self.allowedPageSize.contains(limit) else {
      throw DaemonUsageError.pageLimit(Self.allowedPageSize)
    }
  }

  func run() async throws {
    let command = self
    try await runCancellable { try await command.serve() }
  }

  private func serve() async throws {
    let context = try options.load()
    try await select(model, in: context)
    let adapter = context.adapter(allowingActions: actions)
    let sweeper = MailSweeper(
      source: adapter,
      store: context.store,
      pipeline: Pipeline(store: context.store, classifier: context.classifier()),
      scope: .allAccounts
    )
    guard let pollSeconds else {
      return try await sweep(with: sweeper, adapter: adapter, context: context)
    }
    try await poll(every: pollSeconds) {
      try await sweep(with: sweeper, adapter: adapter, context: context)
    }
  }

  /// Sweeps on an interval, backing off after failures that may clear on their own.
  private func poll(every interval: Int, _ sweep: () async throws -> Void) async throws {
    var failures = 0, authenticationFailures = 0
    while true {
      try Task.checkCancellation()
      do {
        try await sweep()
        failures = 0; authenticationFailures = 0
      } catch {
        let failure = DaemonFailure(error: error)
        if error is CancellationError || Task.isCancelled { throw CancellationError() }
        if failure.isAuthentication { authenticationFailures += 1 }
        guard !failure.isConfiguration,
          authenticationFailures < Self.maximumAuthenticationFailures
        else { throw error }
        failures += 1
        failure.report("Sweep failed; retrying in \(backoff(interval, failures)) seconds")
      }
      try await Task.sleep(for: .seconds(failures == 0 ? interval : backoff(interval, failures)))
    }
  }

  /// The delay after `failures` consecutive failures: the interval, doubling to an hour.
  private func backoff(_ interval: Int, _ failures: Int) -> Int {
    min(Self.maximumBackoffSec, interval << min(failures, Int.bitWidth - 2))
  }

  private func sweep(
    with sweeper: MailSweeper,
    adapter: IMAPAdapter,
    context: DaemonContext
  ) async throws {
    if actions {
      let account = context.configuration.account
      guard
        try await IMAPAccountValidation.isValidated(account, scope: .daemon, store: context.store)
      else { throw IntegrationError.accountUnverified }
    }
    let failures = FailureLog()
    let summary = try await sweeper.sweep(dryRun: !actions, limit: limit) { event in
      if case .accountFailed(_, let error) = event { failures.append(error) }
    }
    if let error = failures.first { throw error }
    guard !summary.paused else { return print("Filtering paused; Inbox not read.") }
    let coverage =
      try await MailHealthRepository.load(context.store, key: adapter.accountID)?
      .coverage ?? SweepCoverage()
    print(
      "Visited \(coverage.visited) messages: \(coverage.classified) classified, "
        + "\(coverage.reviewed) for review, \(coverage.unclassified) unclassified; "
        + (actions
          ? "shared action gates applied."
          : "dry run; previewed mail counts as processed, so live filtering in this store skips it.")
    )
  }

  private func select(_ model: ModelIdentifier?, in context: DaemonContext) async throws {
    guard let model else { return }
    guard !context.usesSharedStore else { throw DaemonUsageError.modelRequiresStatePath }
    try await context.reportingSettingChanges {
      try await StateRepository.editSettings(context.store) { settings in
        var advanced = settings.advancedOptions
        advanced.select(model)
        settings.advancedOptions = advanced
      }
    }
  }
}

/// Failures reported by sweep events, in order.
private final class FailureLog: Sendable {
  private let errors = Mutex<[any Error]>([])
  var first: (any Error)? { errors.withLock { $0.first } }
  func append(_ error: any Error) { errors.withLock { $0.append(error) } }
}
