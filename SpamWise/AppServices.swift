import Foundation
import SpamWiseCore
import MailIntegration

/// The long-lived integrations every feature model draws its dependencies from.
@MainActor
struct AppServices {
  private static let uiTestingArgument = "--ui-testing"
  private static let uiAutomationArgument = "--ui-automation"
  /// Durable shared state; nil when the App Group container could not be opened.
  let store: Store?
  /// Classifies, persists and dispatches messages; nil without a store.
  let pipeline: Pipeline?
  /// Apple Mail through Apple Events.
  let appleMail: AppleMailAdapter
  /// Per-installation interface preferences, isolated while UI testing.
  let preferences: UserDefaults
  /// Whether the app runs under UI tests or previews, which never touch Mail or the shared store.
  let uiTesting: Bool
  var storageReady: Bool { store != nil }

  /// The production services, or isolated fixtures when launched for UI tests.
  static func launched() -> Self {
    let arguments = ProcessInfo.processInfo.arguments
    let uiTesting = arguments.contains(uiTestingArgument)
    let automation = uiTesting && arguments.contains(uiAutomationArgument)
    let store = openStore { try uiTesting ? isolatedStoreURL() : Store.sharedURL() }
    return Self(
      store: store,
      pipeline: store.map { pipeline(for: $0, automationFixture: automation) },
      appleMail: AppleMailAdapter(runner: runner(uiTesting: uiTesting, automation: automation)),
      preferences: uiTesting ? isolatedPreferences() : .standard,
      uiTesting: uiTesting
    )
  }

  /// Services for previews: no store, no pipeline, and Mail denies every request.
  static func preview() -> Self {
    Self(
      store: nil,
      pipeline: nil,
      appleMail: AppleMailAdapter(runner: runner(uiTesting: true, automation: false)),
      preferences: isolatedPreferences(),
      uiTesting: true
    )
  }

  private static func openStore(at url: () throws -> URL) -> Store? {
    do { return try Store(url: url()) } catch {
      DeveloperDiagnostics.recordStorageFailure(error)
      return nil
    }
  }

  private static func isolatedStoreURL() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "SpamWise-UI-\(UUID())/state.store")
  }

  private static func isolatedPreferences() -> UserDefaults {
    guard let isolated = UserDefaults(suiteName: "codes.tim.SpamWise.ui.\(UUID())") else {
      preconditionFailure("UI fixtures require an isolated preferences suite.")
    }
    return isolated
  }

  private static func pipeline(for store: Store, automationFixture: Bool) -> Pipeline {
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
      classifier: ConfiguredClassifier(store: store),
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
      credentials: {
        let value = try APIKeychain(service: connection.credentialService).read()
        return connection.oauthBearer ? .oauthBearer(value) : .password(value)
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
