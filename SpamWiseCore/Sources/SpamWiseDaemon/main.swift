import Foundation
import Dispatch
import Darwin
import SpamWiseCore
import MailIntegration

@main
struct SpamWiseDaemon {
  private static let maximumConfigurationBytes = 65_536
  private static let dryRunNote =
    "dry run; previewed mail counts as processed, so live filtering in this store skips it"
  private static let usage = """
    spamwise-daemon --config path [--once | --poll-seconds 60...3600] [--limit 1...100] [--actions]
      [--model MODEL]
    spamwise-daemon --config path --validate
    spamwise-daemon --config path --probe UID

    Default: one bounded dry run. Classification can send bounded message context to the explicitly
    selected provider; paid requests count toward the store's monthly spending limit, if one is set.
    Actions also require validation recorded for this exact endpoint, the IMAP route and dry run
    disabled in shared settings. --validate records validation and selects the IMAP route when the
    server supports MOVE and has a unique Junk mailbox; otherwise it revokes validation.
    Mail a dry run previews counts as processed: live filtering that shares the store skips it.
    Optional --probe moves only an Inbox message whose subject starts with [SpamWise Probe], then \
    restores it.
    No launch service is installed. SIGINT/SIGTERM cancel pending work. Secrets are never CLI \
    arguments.
    --model selects an explicit supported model in this store; providerCredentials can reference
    provider-specific environment or login Keychain secrets. No provider or credential fallback.
    Models: \(ModelIdentifier.allCases.map(\.rawValue).joined(separator: ", ")).
    """

  static func main() async {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments.isEmpty || arguments == ["--help"] { print(usage); return }
    let task = Task { try await run(arguments) }
    let signals = [SIGINT, SIGTERM].map { number in
      _ = signal(number, SIG_IGN)
      let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
      source.setEventHandler { task.cancel() }
      source.resume()
      return source
    }
    do { try await task.value } catch is CancellationError { print("Stopped.") } catch {
      FileHandle.standardError.write(
        Data(
          "Headless operation failed. Check settings and credentials. Uncertain actions are not retried.\n"
            .utf8
        )
      )
      for source in signals { source.cancel() }
      exit(1)
    }
    for source in signals { source.cancel() }
  }
  private static func run(_ arguments: [String]) async throws {
    let options = try Options(arguments)
    let file = try FileHandle(forReadingFrom: URL(filePath: options.path))
    defer { try? file.close() }
    let data = try file.read(upToCount: maximumConfigurationBytes + 1) ?? Data()
    let configuration = try IMAPDaemonConfiguration.decode(data)
    let store = try Store(
      url: configuration.statePath.map { URL(filePath: $0) } ?? Store.sharedURL()
    )
    try await selectModel(options.model, store: store)
    var account = configuration.account
    account.allowsActions = options.actions
    let credential = configuration.credential
    let adapter = IMAPAdapter(
      configuration: account,
      credentials: { try credential.resolve() },
      validations: store
    )
    let check = try await adapter.validateReadOnly()
    if options.validate {
      try await recordValidation(check, for: account, store: store); return
    }
    if let uid = options.probe {
      _ = try await adapter.testDisposableMessage(uid: uid)
      try await IMAPAccountValidation.record(account, store: store)
      print(
        "Disposable probe restored to Inbox; endpoint validation recorded. Dry run remains unchanged."
      )
      return
    }
    let classifier: ConfiguredClassifier
    if let references = configuration.providerCredentials {
      classifier = ConfiguredClassifier(store: store) { backend in
        guard let reference = references[backend.rawValue] else {
          throw ClassificationError.missingCredential
        }
        return try reference.resolvedSecret()
      }
    } else {
      classifier = ConfiguredClassifier(store: store)
    }
    let pipeline = Pipeline(store: store, classifier: classifier)
    repeat {
      try Task.checkCancellation()
      if options.actions {
        guard try await IMAPAccountValidation.isValidated(account, store: store) else {
          throw IntegrationError.accountUnverified
        }
      }
      if try await StateRepository.load(store, StateSlices()).settings.paused {
        print("Filtering paused; Inbox not read.")
      } else {
        let processed = try await sweep(adapter, with: pipeline, store: store, options: options)
        print(
          "Processed \(processed) messages; \(options.actions ? "shared action gates applied" : Self.dryRunNote)."
        )
      }
      guard let interval = options.poll else { return }
      try await Task.sleep(for: .seconds(interval))
    } while !Task.isCancelled
  }

  private static func recordValidation(
    _ check: IMAPValidation,
    for account: IMAPConfiguration,
    store: Store
  ) async throws {
    if try await IMAPAccountValidation.record(check, for: account, store: store) {
      print(
        "Read-only check passed; Inbox and Junk validated for this endpoint. Dry run unchanged."
      )
    } else {
      print(
        "Read-only check passed, but the server lacks MOVE or a unique Junk mailbox; not validated."
      )
    }
  }

  private static func sweep(
    _ adapter: IMAPAdapter,
    with pipeline: Pipeline,
    store: Store,
    options: Options
  ) async throws -> Int {
    let sweep = try await adapter.nextInboxSweep(limit: options.limit, cursorStore: store)
    if options.actions {
      _ = await pipeline.correctMailReturnedFromJunk(sweep.messages, adapter: adapter)
    }
    let processed = try await pipeline.processBatch(
      sweep.messages,
      adapter: adapter,
      dryRun: !options.actions,
      skipsSettled: true,
      onCompletion: { try await adapter.commit(sweep, cursorStore: store) }
    ).count
    if options.actions { await pipeline.retryDue(adapter: adapter, accountID: adapter.accountID) }
    return processed
  }

  private static func selectModel(_ model: ModelIdentifier?, store: Store) async throws {
    guard let model else { return }
    let current = try await StateRepository.load(store, StateSlices()).settings.advancedOptions
    guard current.model != model else { return }
    try await StateRepository.editSettings(store) { settings in
      var advanced = settings.advancedOptions
      advanced.select(model)
      settings.advancedOptions = advanced
    }
  }

  private struct Options {
    private static let allowedPollSeconds = 60...3600
    private static let allowedPageSize = 1...100
    private static let defaultPageSize = 20
    var path: String
    var actions = false
    var validate = false
    var probe: UInt32?
    var poll: Int?
    var limit = Self.defaultPageSize
    var model: ModelIdentifier?
    init(_ arguments: [String]) throws {
      var values: [String: String] = [:], flags: Set<String> = []
      var offset = 0
      while offset < arguments.count {
        let name = arguments[offset]; offset += 1
        if ["--actions", "--once", "--validate"].contains(name) {
          guard flags.insert(name).inserted else { throw IMAPError.invalidConfiguration }
        } else {
          guard ["--config", "--probe", "--poll-seconds", "--limit", "--model"].contains(name),
            offset < arguments.count, values[name] == nil
          else { throw IMAPError.invalidConfiguration }
          values[name] = arguments[offset]; offset += 1
        }
      }
      guard let path = values["--config"], !path.isEmpty else {
        throw IMAPError.invalidConfiguration
      }
      self.path = path
      actions = flags.contains("--actions")
      validate = flags.contains("--validate")
      if let identifier = values["--model"] {
        guard let model = ModelIdentifier(rawValue: identifier) else {
          throw IMAPError.invalidConfiguration
        }
        self.model = model
      }
      if let value = values["--probe"] {
        guard let uid = UInt32(value), uid > 0 else { throw IMAPError.invalidConfiguration }
        probe = uid
      }
      if let value = values["--poll-seconds"] {
        guard let seconds = Int(value), Self.allowedPollSeconds.contains(seconds) else {
          throw IMAPError.invalidConfiguration
        }; poll = seconds
      }
      if let value = values["--limit"] {
        guard let count = Int(value), Self.allowedPageSize.contains(count) else {
          throw IMAPError.invalidConfiguration
        }; limit = count
      }
      guard !(flags.contains("--once") && poll != nil),
        !(validate && (probe != nil || actions || poll != nil || model != nil)),
        !(probe != nil && (actions || poll != nil || model != nil))
      else { throw IMAPError.invalidConfiguration }
    }
  }
}
