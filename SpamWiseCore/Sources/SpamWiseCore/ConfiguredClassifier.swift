import Foundation

/// Resolves explicit provider settings for every request without silently changing backends.
public struct ConfiguredClassifier: Classifier {
  private let store: Store
  private let http: ModelHTTPClient
  private let credential: @Sendable (ModelBackend) throws -> String
  /// Reads current settings with optional HTTP and provider-specific credential boundaries.
  public init(
    store: Store,
    http: ModelHTTPClient = .live,
    credential: @escaping @Sendable (ModelBackend) throws -> String = { backend in
      try APIKeychain(service: ConfiguredClassifier.credentialService(for: backend)).read()
    }
  ) {
    self.store = store
    self.http = http
    self.credential = credential
  }
  /// Returns the credential service for a paid provider; credentials are never persisted in preferences.
  public static func credentialService(for backend: ModelBackend) -> String {
    backend == .claude
      ? "codes.tim.SpamWise.anthropic" : "codes.tim.SpamWise." + backend.rawValue.lowercased()
  }
  /// Executes one explicitly selected backend, counting paid requests toward the monthly spending limit.
  public func classify(_ input: ClassificationInput) async throws -> Verdict {
    let current = try await StateRepository.load(store).settings
    let settings = current.advancedOptions
    guard !current.mailOptions.localOnly || settings.backend == .onDevice else {
      throw ClassificationError.configuration
    }
    guard
      settings.backend == .onDevice
        || settings.mailSharingConsent?.contains(settings.backend) == true
    else {
      throw ClassificationError.consentRequired
    }
    let modelID = settings.modelID ?? settings.backend.defaultModelID
    switch settings.backend {
      case .onDevice: return try await AppleClassifier(backend: .onDevice).classify(input)
      case .privateCloudCompute:
        guard DistributionCapabilities.privateCloudCompute else {
          throw ClassificationError.configuration
        }
        return try await AppleClassifier(backend: .privateCloudCompute).classify(input)
      case .claude, .openAI, .gemini:
        let key = try credential(settings.backend)
        guard !key.isEmpty else { throw ClassificationError.configuration }
        let classifier: any Classifier
        switch settings.backend {
          case .claude: classifier = try ClaudeClassifier(modelID: modelID, key: { key })
          case .openAI:
            classifier = try OpenAIClassifier(modelID: modelID, key: { key }, http: http)
          case .gemini:
            classifier = try GeminiClassifier(modelID: modelID, key: { key }, http: http)
          default: throw ClassificationError.configuration
        }
        return try await SpendingLimitedClassifier(
          ConsentCheckedClassifier(underlying: classifier, store: store, backend: settings.backend),
          modelID: modelID,
          store: store
        ).classify(input)
    }
  }
}

private struct ConsentCheckedClassifier: Classifier {
  let underlying: any Classifier
  let store: Store
  let backend: ModelBackend

  func classify(_ input: ClassificationInput) async throws -> Verdict {
    let current = try await StateRepository.load(store).settings
    guard !current.mailOptions.localOnly,
      current.advancedOptions.backend == backend,
      current.advancedOptions.mailSharingConsent?.contains(backend) == true
    else { throw ClassificationError.consentRequired }
    try Task.checkCancellation()
    return try await underlying.classify(input)
  }
}
