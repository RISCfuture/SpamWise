import Foundation
import ClaudeForFoundationModels

/// Explicit classifier selection; unavailable backends never fall back to another provider.
public enum ModelBackend: String, Codable, Sendable, CaseIterable {
  /// Uses the explicitly selected Claude model.
  case claude
  /// Uses Apple’s available on-device model.
  case onDevice
  /// Uses Apple’s explicitly authorized Private Cloud Compute model.
  case privateCloudCompute
  /// Uses the supported OpenAI Responses model.
  case openAI
  /// Uses the supported Gemini model.
  case gemini

  /// Model selected when this provider is chosen without an explicit model.
  public var defaultModel: ModelIdentifier {
    switch self {
      case .claude: .claudeHaiku
      case .onDevice: .appleOnDevice
      case .privateCloudCompute: .applePrivateCloudCompute
      case .openAI: .gptMini
      case .gemini: .geminiFlash
    }
  }
}

/// The closed set of supported models; raw values are the stable persisted and wire identities.
public enum ModelIdentifier: String, Codable, Sendable, CaseIterable {
  /// Claude Haiku 5.5, the default provider model.
  case claudeHaiku = "claude-haiku-5-5"
  /// Claude Sonnet 5.5.
  case claudeSonnet = "claude-sonnet-5-5"
  /// Claude Opus 5.5.
  case claudeOpus = "claude-opus-5-5"
  /// OpenAI GPT-5.4 mini.
  case gptMini = "gpt-5.4-mini"
  /// Google Gemini 3.8 Flash.
  case geminiFlash = "gemini-3.8-flash"
  /// Apple’s on-device Foundation Model.
  case appleOnDevice = "apple-on-device"
  /// Apple’s Private Cloud Compute Foundation Model.
  case applePrivateCloudCompute = "apple-private-cloud-compute"

  private static let lowCostReservationUSD = 0.10
  private static let standardReservationUSD = 1.0

  /// Provider that serves this model.
  public var backend: ModelBackend {
    switch self {
      case .claudeHaiku, .claudeSonnet, .claudeOpus: .claude
      case .gptMini: .openAI
      case .geminiFlash: .gemini
      case .appleOnDevice: .onDevice
      case .applePrivateCloudCompute: .privateCloudCompute
    }
  }

  /// Presentation name for settings and reports.
  public var displayName: String {
    switch self {
      case .claudeHaiku: "Claude Haiku 5.5"
      case .claudeSonnet: "Claude Sonnet 5.5"
      case .claudeOpus: "Claude Opus 5.5"
      case .gptMini: "GPT-5.4 mini"
      case .geminiFlash: "Gemini 3.8 Flash"
      case .appleOnDevice: String(localized: "Apple on-device model")
      case .applePrivateCloudCompute: String(localized: "Apple Private Cloud Compute model")
    }
  }

  /// Conservative per-request spending reservation in USD; nil for models without API charges.
  public var reservationUSD: Double? {
    switch self {
      case .claudeHaiku: Self.lowCostReservationUSD
      case .claudeSonnet, .claudeOpus, .gptMini, .geminiFlash:
        Self.standardReservationUSD
      case .appleOnDevice, .applePrivateCloudCompute: nil
    }
  }

  var claudeModel: ClaudeModel? {
    switch self {
      case .claudeHaiku: .haiku5_5
      case .claudeSonnet: .sonnet5_5
      case .claudeOpus: .opus5_5
      case .gptMini, .geminiFlash, .appleOnDevice, .applePrivateCloudCompute: nil
    }
  }
}

/// Builds the one classifier that serves an explicitly selected model, without provider fallback.
public enum ClassifierFactory {
  /**
   Returns the classifier for `model`.

   - Parameters:
     - model: The explicitly selected model; its backend chooses the provider.
     - credential: Reads the provider API key; Apple models never call it.
     - http: HTTP boundary for the OpenAI and Gemini REST backends.
   */
  public static func make(
    _ model: ModelIdentifier,
    credential: @escaping @Sendable () throws -> String,
    http: ModelHTTPClient = .live
  ) -> any Classifier {
    switch model.backend {
      case .claude: ClaudeClassifier(model: model, key: credential)
      case .openAI: OpenAIClassifier(model: model, key: credential, http: http)
      case .gemini: GeminiClassifier(model: model, key: credential, http: http)
      case .onDevice: AppleClassifier(backend: .onDevice)
      case .privateCloudCompute: AppleClassifier(backend: .privateCloudCompute)
    }
  }
}
