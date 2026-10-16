import Foundation

/// Resolves explicit provider settings for every request without silently changing backends.
public struct ConfiguredClassifier: Classifier {
  private static let haikuReservationUSD = 0.10
  private static let otherModelReservationUSD = 1.0
  private let store: Store
  private let credential: @Sendable (ModelBackend) throws -> String
  /// Reads current settings with an optional provider-specific credential boundary.
  public init(
    store: Store,
    credential: @escaping @Sendable (ModelBackend) throws -> String = { backend in
      try APIKeychain(service: ConfiguredClassifier.credentialService(for: backend)).read()
    }
  ) {
    self.store = store
    self.credential = credential
  }
  /// Returns the credential service for a paid provider; credentials are never persisted in preferences.
  public static func credentialService(for backend: ModelBackend) -> String {
    backend == .claude
      ? "codes.tim.SpamWise.anthropic" : "codes.tim.SpamWise." + backend.rawValue.lowercased()
  }
  /// Executes one explicitly selected backend with conservative spending reservations where applicable.
  public func classify(_ input: ClassificationInput) async throws -> Verdict {
    let current = try await StateRepository.load(store).settings
    let settings = current.advancedOptions
    guard !current.mailOptions.localOnly || settings.backend == .onDevice else {
      throw ClassificationError.configuration
    }
    let modelID = settings.modelID ?? settings.backend.defaultModelID
    switch settings.backend {
      case .onDevice: return try await AppleClassifier(backend: .onDevice).classify(input)
      case .privateCloudCompute:
        return try await AppleClassifier(backend: .privateCloudCompute).classify(input)
      case .claude, .openAI, .gemini:
        let key = try credential(settings.backend)
        guard !key.isEmpty else { throw ClassificationError.configuration }
        let classifier: any Classifier
        switch settings.backend {
          case .claude: classifier = try ClaudeClassifier(modelID: modelID, key: { key })
          case .openAI: classifier = try OpenAIClassifier(modelID: modelID, key: { key })
          case .gemini: classifier = try GeminiClassifier(modelID: modelID, key: { key })
          default: throw ClassificationError.configuration
        }
        _ = try PromptBuilder.prompt(input)
        return try await BudgetedClassifier(
          classifier,
          store: store,
          upperBoundUSD: modelID == "claude-haiku-5-5"
            ? Self.haikuReservationUSD : Self.otherModelReservationUSD
        ).classify(input)
    }
  }
}
