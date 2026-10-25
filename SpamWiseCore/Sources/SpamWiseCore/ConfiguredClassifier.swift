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
  /// The selected model, once local-only mode, mail-sharing consent and the backend permit a request.
  private static func requestableModel(_ settings: Settings) throws -> ModelIdentifier {
    let options = settings.advancedOptions
    guard !settings.mailOptions.localOnly || options.backend == .onDevice else {
      throw ClassificationError.configuration
    }
    guard options.backend == .onDevice || options.mailSharingConsent.contains(options.backend)
    else {
      throw ClassificationError.consentRequired
    }
    guard options.backend != .privateCloudCompute else {
      throw ClassificationError.configuration
    }
    return options.model
  }
  /// Executes one explicitly selected backend, counting paid requests toward the monthly spending limit.
  public func classify(_ input: ClassificationInput) async throws -> Verdict {
    let settings = try await StateRepository.load(store, StateSlices()).settings
    let model = try Self.requestableModel(settings)
    guard model.reservationUSD != nil else {
      return try await ClassifierFactory.make(model, credential: { "" }).classify(input)
    }
    let backend = settings.advancedOptions.backend
    let key = try providerKey(backend)
    return try await SpendingLimitedClassifier(
      ConsentCheckedClassifier(
        underlying: ClassifierFactory.make(model, credential: { key }, http: http),
        store: store,
        backend: backend
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

extension ConfiguredClassifier: SpendingAdmission {
  /// Whether the spending limit leaves room for `input`, admitting a request that never reaches a paid provider so ``classify(_:)`` reports why.
  func admits(_ input: ClassificationInput) async throws -> Bool {
    let settings = try await StateRepository.load(store, StateSlices()).settings
    guard let model = try? Self.requestableModel(settings), model.reservationUSD != nil,
      (try? providerKey(settings.advancedOptions.backend)) != nil
    else { return true }
    return try await SpendingLimit.admits(input, model: model, store: store)
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
