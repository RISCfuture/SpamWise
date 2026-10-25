import Foundation
import SpamWiseCore
import MailIntegration

/// The long-lived integrations every feature model draws its dependencies from.
@MainActor
struct AppServices {
  private static let isolatedStorePrefix = "SpamWise-UI-"
  private static let isolatedPreferencesPrefix = "codes.tim.SpamWise.ui."

  #if DEBUG
    private static let uiTestingArgument = "--ui-testing"
    private static let uiAutomationArgument = "--ui-automation"
    /// How long an isolated store or preferences suite is kept after the launch that made it.
    private static let isolatedStateLifetimeSec: TimeInterval = 86_400
  #endif

  /// Durable shared state; nil when the App Group container could not be opened.
  let store: Store?
  /// Classifies, persists and dispatches messages; nil without a store.
  let pipeline: Pipeline?
  /// Apple Mail through Apple Events.
  let appleMail: AppleMailAdapter
  /// Per-installation interface preferences, isolated while UI testing.
  let preferences: UserDefaults
  /// API keys and passwords: the shared Keychain, or memory while UI testing.
  let credentials: any CredentialStore
  /// Whether the app runs under UI tests or previews, which never touch Mail or the shared store.
  let uiTesting: Bool
  var storageReady: Bool { store != nil }

  /// The production services, or isolated fixtures when a debug build is launched for UI tests.
  static func launched() -> Self {
    let arguments = ProcessInfo.processInfo.arguments
    let uiTesting = isUITesting(arguments)
    let automation = uiTesting && isUIAutomation(arguments)
    #if DEBUG
      if uiTesting { removeStaleIsolatedState() }
    #endif
    let store = openStore { try uiTesting ? isolatedStoreURL() : Store.sharedURL() }
    let credentials: any CredentialStore =
      uiTesting ? MemoryCredentialStore() : KeychainCredentialStore()
    return Self(
      store: store,
      pipeline: store.map {
        pipeline(for: $0, credentials: credentials, automationFixture: automation)
      },
      appleMail: AppleMailAdapter(
        runner: runner(uiTesting: uiTesting, automation: automation),
        reviewMarks: store
      ),
      preferences: uiTesting ? isolatedPreferences() : .standard,
      credentials: credentials,
      uiTesting: uiTesting
    )
  }

  /// Services for previews: no store, no pipeline, no Keychain, and Mail denies every request.
  static func preview() -> Self {
    Self(
      store: nil,
      pipeline: nil,
      appleMail: AppleMailAdapter(runner: runner(uiTesting: true, automation: false)),
      preferences: isolatedPreferences(),
      credentials: MemoryCredentialStore(),
      uiTesting: true
    )
  }

  /// Whether a debug build was launched for UI tests; release builds never are.
  private static func isUITesting(_ arguments: [String]) -> Bool {
    #if DEBUG
      arguments.contains(uiTestingArgument)
    #else
      false
    #endif
  }

  /// Whether a debug build's UI tests act on fixture messages; release builds never do.
  private static func isUIAutomation(_ arguments: [String]) -> Bool {
    #if DEBUG
      arguments.contains(uiAutomationArgument)
    #else
      false
    #endif
  }

  private static func openStore(at url: () throws -> URL) -> Store? {
    do { return try Store(url: url()) } catch {
      DeveloperDiagnostics.recordStorageFailure(error)
      return nil
    }
  }

  private static func isolatedStoreURL() -> URL {
    FileManager.default.temporaryDirectory.appending(
      path: "\(isolatedStorePrefix)\(UUID())/state.store"
    )
  }

  private static func isolatedPreferences() -> UserDefaults {
    guard let isolated = UserDefaults(suiteName: "\(isolatedPreferencesPrefix)\(UUID())") else {
      preconditionFailure("UI fixtures require an isolated preferences suite.")
    }
    return isolated
  }

  private static func pipeline(
    for store: Store,
    credentials: any CredentialStore,
    automationFixture: Bool
  ) -> Pipeline {
    #if DEBUG
      if automationFixture {
        return Pipeline(
          store: store,
          classifier: MockClassifier(
            verdict: .init(label: .junk, confidence: 99, reason: "Synthetic unwanted newsletter")
          )
        )
      }
    #endif
    return Pipeline(
      store: store,
      classifier: ConfiguredClassifier(store: store) { try credentials.read(.provider($0)) },
      rdap: RDAPLookup(
        cacheURL: store.url.deletingLastPathComponent().appending(path: "rdap-cache.json")
      )
    )
  }

  private static func runner(uiTesting: Bool, automation: Bool) -> any AppleEventRunner {
    #if DEBUG
      if automation { return SelectedFixtureAppleEventRunner() }
      if uiTesting { return DeniedAppleEventRunner() }
    #endif
    return SystemAppleEventRunner()
  }

  /// The store, or the error that explains why shared storage is unavailable.
  func requireStore() throws -> Store {
    guard let store else { throw SharedStorageError.unavailable }
    return store
  }

  /// The pipeline, or the error that explains why shared storage is unavailable.
  func requirePipeline() throws -> Pipeline {
    guard let pipeline else { throw SharedStorageError.unavailable }
    return pipeline
  }
}

#if DEBUG
  extension AppServices {
    /**
     Removes the isolated stores and preferences suites that earlier UI-testing launches left.

     Only those unchanged for ``isolatedStateLifetimeSec`` are removed, so a concurrent run keeps
     its own.
     */
    private static func removeStaleIsolatedState(now: Date = .now) {
      let fileManager = FileManager.default
      let cutoff = now.addingTimeInterval(-isolatedStateLifetimeSec)
      let stores = items(
        in: fileManager.temporaryDirectory,
        prefix: isolatedStorePrefix,
        modifiedBefore: cutoff
      )
      for store in stores { try? fileManager.removeItem(at: store) }
      guard let library = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first
      else { return }
      let suites = items(
        in: library.appending(path: "Preferences"),
        prefix: isolatedPreferencesPrefix,
        modifiedBefore: cutoff
      )
      for suite in suites where suite.pathExtension == "plist" {
        UserDefaults.standard.removePersistentDomain(
          forName: suite.deletingPathExtension().lastPathComponent
        )
        try? fileManager.removeItem(at: suite)
      }
    }

    private static func items(in directory: URL, prefix: String, modifiedBefore cutoff: Date)
      -> [URL]
    {
      let key = URLResourceKey.contentModificationDateKey
      let contents =
        (try? FileManager.default.contentsOfDirectory(
          at: directory,
          includingPropertiesForKeys: [key]
        )) ?? []
      return contents.filter { item in
        let modified = try? item.resourceValues(forKeys: [key]).contentModificationDate
        return item.lastPathComponent.hasPrefix(prefix) && (modified ?? .distantFuture) < cutoff
      }
    }
  }
#endif

extension AppServices {
  /// An adapter for the saved IMAP connection; actions stay gated by the persisted account validation.
  func imapAdapter() async throws -> IMAPAdapter {
    let store = try requireStore()
    guard let connection = try await IMAPAppConnection.saved(in: store) else {
      throw IMAPSetupError.noSavedConnection
    }
    var configuration = connection.account
    configuration.allowsActions = true
    return IMAPAdapter(
      configuration: configuration,
      credentials: { [credentials] in
        .password(try credentials.read(.imap(service: connection.credentialService)))
      },
      validations: store
    )
  }

  /// The integration that addresses `record`'s message: IMAP for IMAP identities, Apple Mail otherwise.
  func adapter(for record: DecisionRecord) async throws -> any MailClientAdapter {
    record.identity.mailboxValidity == nil ? appleMail : try await imapAdapter()
  }

  /// The mail source of `transport`.
  func sweepSource(for transport: MailTransport) async throws -> any MailSweepSource {
    transport == .imap ? try await imapAdapter() : appleMail
  }

  /**
   A sweeper over `source`, which defaults to `transport`'s source.

   An IMAP connection sweeps every account it reports; Apple Mail sweeps the configured accounts
   and folder plans.
   */
  func sweeper(
    transport: MailTransport,
    source: (any MailSweepSource)? = nil
  ) async throws -> MailSweeper {
    let imap = source == nil && transport == .imap
    let selected: any MailSweepSource
    if let source { selected = source } else { selected = try await sweepSource(for: transport) }
    return MailSweeper(
      source: selected,
      store: try requireStore(),
      pipeline: try requirePipeline(),
      scope: imap ? .allAccounts : .configured,
      describe: { OperationFailure.describe($0) }
    )
  }
}
