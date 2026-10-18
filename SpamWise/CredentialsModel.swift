import Foundation
import Observation
import SpamWiseCore

/// Provider and lookup-service keys, stored only in Keychain.
@MainActor @Observable final class CredentialsModel {
  private static let verificationMessage = """
    From: setup@example.org
    Subject: API connection check

    Hello. This is a synthetic SpamWise connection test.
    """
  private static let providerCheckInterval: Duration = .seconds(60)
  /// Verifying and saving the Anthropic key.
  let claudeKey = TrackedOperation()
  /// Saving an OpenAI or Gemini key.
  let providerKey = TrackedOperation()
  /// Reading and saving the Spamhaus query key.
  let spamhausKey = TrackedOperation()
  /// The providers whose API keys are saved in Keychain, as of the latest check or save.
  private(set) var savedKeys: Set<ModelBackend> = []
  /// Reading which credentials are saved, and removing them.
  let storedCredentials = TrackedOperation()
  /// Whether each credential SpamWise can store is saved, as last read.
  private(set) var saved: [StoredCredential: StoredCredential.State] = [:]
  /// The selected provider, while it needs an API key and Keychain holds none.
  private(set) var missingProviderKey: ModelBackend?
  @ObservationIgnored private let services: AppServices
  @ObservationIgnored private var checkedProvider: ModelBackend?
  @ObservationIgnored private var lastProviderCheck: ContinuousClock.Instant?

  init(services: AppServices) { self.services = services }

  @concurrent private static func save(_ credential: String, in keychain: APIKeychain?)
    async throws
  {
    guard let keychain else { throw ClassificationError.configuration }
    try keychain.save(credential)
  }

  @concurrent private static func providersWithSavedKeys() async -> Set<ModelBackend> {
    Set(
      ModelBackend.allCases.filter { backend in
        (try? APIKeychain(backend: backend)?.exists()) == true
      }
    )
  }

  @concurrent private static func spamhausKeyStatus() async throws -> String {
    try APIKeychain(service: APIKeychain.spamhausService).exists()
      ? String(localized: "Query key saved in Keychain") : String(localized: "No query key saved")
  }

  /// Whether `credential` is saved, read from its attributes without loading the secret.
  @concurrent private static func exists(_ credential: StoredCredential) async throws -> Bool {
    try credential.keychain?.exists() ?? false
  }

  @concurrent private static func delete(_ credentials: [StoredCredential]) async throws {
    for credential in credentials { try credential.keychain?.delete() }
  }

  private static func recordVerification(
    _ verdict: Verdict,
    message: ParsedMessage,
    store: Store
  ) async throws {
    let record = DecisionRecord(
      identity: .init(accountID: nil, contentHash: message.hash),
      verdict: verdict,
      decision: .init(label: .inbox, action: .none, reason: .connectionVerified),
      outcome: .noAction,
      path: .verification
    )
    try await StateRepository.update(store, loading: StateSlices()) { $0.record(record) }
  }

  /// Checks which providers have API keys saved in Keychain.
  func refreshSavedKeys() async {
    savedKeys = await Self.providersWithSavedKeys()
  }

  /// Sends one synthetic message to the Claude `model` with `key`, then saves the key if it works.
  @discardableResult func verifyClaudeKey(_ key: String, model: ModelIdentifier = .claudeHaiku)
    -> Task<Void, Never>
  {
    precondition(model.backend == .claude, "Only Claude keys are verified with a request.")
    let credential = key.trimmingCharacters(in: .whitespacesAndNewlines)
    return claudeKey.run { [self] in
      guard !credential.isEmpty else { throw ClassificationError.missingCredential }
      let store = try services.requireStore()
      let message = try MIMEParser().parse(Data(Self.verificationMessage.utf8))
      let verdict = try await SpendingLimitedClassifier(
        ClaudeClassifier(model: model, key: { credential }),
        model: model,
        store: store
      ).classify(.init(message: message, evidence: .init(message: message)))
      try await Self.save(credential, in: APIKeychain(backend: .claude))
      recordSaved(.provider(.claude))
      try await Self.recordVerification(verdict, message: message, store: store)
      return String(localized: "Verified — stored in Keychain")
    }
  }

  /// Saves `key` for `backend` without making a request.
  @discardableResult func saveProviderKey(_ key: String, for backend: ModelBackend)
    -> Task<Void, Never>
  {
    let credential = key.trimmingCharacters(in: .whitespacesAndNewlines)
    return providerKey.run { [self] in
      guard !credential.isEmpty else { throw ClassificationError.missingCredential }
      try await Self.save(credential, in: APIKeychain(backend: backend))
      recordSaved(.provider(backend))
      return String(localized: "Provider key saved in Keychain. Use a dry run to verify.")
    }
  }

  /// Reports whether a Spamhaus query key is saved.
  func refreshSpamhausKeyStatus() {
    spamhausKey.run { try await Self.spamhausKeyStatus() }
  }

  /// Saves the Spamhaus query key, then reports that it is saved.
  func saveSpamhausKey(_ key: String) {
    spamhausKey.run { [self] in
      try await Self.save(key, in: APIKeychain(service: APIKeychain.spamhausService))
      recordSaved(.spamhaus)
      return try await Self.spamhausKeyStatus()
    }
  }
}

extension CredentialsModel {
  /**
   Rereads whether each credential is saved: every provider key, the Spamhaus key and the saved
   IMAP connection's password.

   A Keychain failure leaves that credential unknown and is reported, never shown as not saved.
   */
  func refreshSaved() {
    storedCredentials.run(retryable: true) { [self] in
      var found: [StoredCredential: StoredCredential.State] = [:]
      var failure: (any Error)?
      for credential in try await allCredentials() {
        do {
          found[credential] = try await exists(credential) ? .saved : .notSaved
        } catch {
          found[credential] = .unknown
          failure = failure ?? error
        }
      }
      saved = found
      if let failure { throw failure }
      return nil
    }
  }

  /**
   Checks whether `backend` needs a key that Keychain doesn't hold, for the missing-key banner.

   Rechecks at once when the provider changes, and otherwise at most once a minute.
   */
  func checkProviderKeyIfDue(for backend: ModelBackend) async {
    if backend == checkedProvider, let lastProviderCheck,
      .now - lastProviderCheck < Self.providerCheckInterval
    {
      return
    }
    lastProviderCheck = .now
    checkedProvider = backend
    guard StoredCredential.providers.contains(backend) else {
      missingProviderKey = nil
      return
    }
    let keyExists = try? await exists(.provider(backend))
    missingProviderKey = keyExists == false ? backend : nil
  }

  /// Removes one credential from Keychain.
  func remove(_ credential: StoredCredential) {
    storedCredentials.run { [self] in
      try await Self.delete([credential])
      recordRemoved(credential)
      return String(localized: "Removed the \(credential.localizedTitle) from Keychain.")
    }
  }

  /// Removes every credential SpamWise stores from Keychain.
  func removeAll() {
    storedCredentials.run { [self] in
      let credentials = try await allCredentials()
      try await Self.delete(credentials)
      for credential in credentials { recordRemoved(credential) }
      return String(localized: "Removed every SpamWise key and password from Keychain.")
    }
  }

  /// Whether `credential` is saved; previews and UI tests never read the shared Keychain.
  private func exists(_ credential: StoredCredential) async throws -> Bool {
    services.uiTesting ? false : try await Self.exists(credential)
  }

  private func allCredentials() async throws -> [StoredCredential] {
    var credentials = StoredCredential.providers.map(StoredCredential.provider) + [.spamhaus]
    if let store = services.store, let imap = try await IMAPAppConnection.saved(in: store) {
      credentials.append(.imap(service: imap.credentialService))
    }
    return credentials
  }

  private func recordSaved(_ credential: StoredCredential) {
    if saved[credential] != nil { saved[credential] = .saved }
    guard case .provider(let backend) = credential else { return }
    savedKeys.insert(backend)
    if missingProviderKey == backend { missingProviderKey = nil }
  }

  private func recordRemoved(_ credential: StoredCredential) {
    if saved[credential] != nil { saved[credential] = .notSaved }
    guard case .provider(let backend) = credential else { return }
    savedKeys.remove(backend)
    if checkedProvider == backend { missingProviderKey = backend }
  }
}
