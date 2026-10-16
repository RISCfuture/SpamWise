import Foundation

/// Resolves explicit provider settings for every request without silently changing backends.
public struct ConfiguredClassifier: Classifier {
  private let store: Store
  private let http: ModelHTTPClient
  private let credential: @Sendable (ModelBackend) throws -> String
  /// Creates a classifier that reads the selected model from `store` at each request, using `http` and `credential`.
  public init(
    store: Store,
    http: ModelHTTPClient = .live,
    credential: @escaping @Sendable (ModelBackend) throws -> String = Self.keychainCredential
  ) {
    self.store = store
    self.http = http
    self.credential = credential
  }
  /// Reads the shared-Keychain API key for a paid provider; credentials are never persisted in preferences.
  public static func keychainCredential(for backend: ModelBackend) throws -> String {
    guard let keychain = APIKeychain(backend: backend) else {
      throw ClassificationError.configuration
    }
    return try keychain.read()
  }
  /// Executes one explicitly selected backend, counting paid requests toward the monthly spending limit.
  public func classify(_ input: ClassificationInput) async throws -> Verdict {
    let current = try await StateRepository.load(store, StateSlices()).settings
    let settings = current.advancedOptions
    guard !current.mailOptions.localOnly || settings.backend == .onDevice else {
      throw ClassificationError.configuration
    }
    guard
      settings.backend == .onDevice
        || settings.mailSharingConsent.contains(settings.backend)
    else {
      throw ClassificationError.consentRequired
    }
    guard settings.backend != .privateCloudCompute else {
      throw ClassificationError.configuration
    }
    let model = settings.model
    guard model.reservationUSD != nil else {
      return try await ClassifierFactory.make(model, credential: { "" }).classify(input)
    }
    let key = try providerKey(settings.backend)
    return try await SpendingLimitedClassifier(
      ConsentCheckedClassifier(
        underlying: ClassifierFactory.make(model, credential: { key }, http: http),
        store: store,
        backend: settings.backend
      ),
      model: model,
      store: store
    ).classify(input)
  }

  private func providerKey(_ backend: ModelBackend) throws -> String {
    let key: String
    do { key = try credential(backend) } catch KeychainError.missing {
      throw ClassificationError.missingCredential
    }
    guard !key.isEmpty else { throw ClassificationError.missingCredential }
    return key
  }
}

private struct ConsentCheckedClassifier: Classifier {
  let underlying: any Classifier
  let store: Store
  let backend: ModelBackend

  func classify(_ input: ClassificationInput) async throws -> Verdict {
    let current = try await StateRepository.load(store, StateSlices()).settings
    guard !current.mailOptions.localOnly,
      current.advancedOptions.backend == backend,
      current.advancedOptions.mailSharingConsent.contains(backend)
    else { throw ClassificationError.consentRequired }
    try Task.checkCancellation()
    return try await underlying.classify(input)
  }
}
