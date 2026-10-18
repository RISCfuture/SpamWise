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
  /// Verifying and saving the Anthropic key.
  let claudeKey = TrackedOperation()
  /// Saving an OpenAI or Gemini key.
  let providerKey = TrackedOperation()
  /// Reading and saving the Spamhaus query key.
  let spamhausKey = TrackedOperation()
  /// The providers whose API keys are saved in Keychain, as of the latest check or save.
  private(set) var savedKeys: Set<ModelBackend> = []
  @ObservationIgnored private let services: AppServices

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
      savedKeys.insert(.claude)
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
      savedKeys.insert(backend)
      return String(localized: "Provider key saved in Keychain. Use a dry run to verify.")
    }
  }

  /// Reports whether a Spamhaus query key is saved.
  func refreshSpamhausKeyStatus() {
    spamhausKey.run { try await Self.spamhausKeyStatus() }
  }

  /// Saves the Spamhaus query key, then reports that it is saved.
  func saveSpamhausKey(_ key: String) {
    spamhausKey.run {
      try await Self.save(key, in: APIKeychain(service: APIKeychain.spamhausService))
      return try await Self.spamhausKeyStatus()
    }
  }

}
