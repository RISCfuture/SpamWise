import Foundation
import FoundationModels
import ClaudeForFoundationModels

/// Guided-generation label whose raw values match ``MailLabel``.
@Generable
enum GuidedLabel: String { case inbox, review, junk }

/// Guided-generation verdict shared by every Foundation Models session.
@Generable
struct GuidedVerdict {
  var label: GuidedLabel
  @Guide(description: "Uncalibrated confidence from 0 through 100", .range(0...100))
  var confidence: Int
  @Guide(description: "One short evidence-grounded sentence, at most 240 characters")
  var reason: String
}

extension Verdict {
  /// Validates a guided response and records the session's measured usage at the model's rates.
  init(guided: GuidedVerdict, session: LanguageModelSession, model: ModelIdentifier) throws {
    guard let label = MailLabel(rawValue: guided.label.rawValue),
      guided.reason.count <= ClassificationLimits.maximumReasonCharacters
    else { throw ClassificationError.invalidOutput }
    let usage = session.usage
    self.init(
      label: label,
      confidence: guided.confidence,
      reason: guided.reason,
      usage: .init(
        input: usage.input.totalTokenCount,
        output: usage.output.totalTokenCount,
        cached: usage.input.cachedTokenCount,
        estimated: false,
        modelID: model.rawValue,
        pricing: .rates(for: model)
      )
    )
    self = try validated()
  }
}

extension ClassificationError {
  /// Maps any provider, framework or transport failure onto the fail-open classification vocabulary.
  init(mapping error: any Error) {
    switch error {
      case let error as ClassificationError: self = error
      case is CancellationError: self = .cancelled
      case let error as LanguageModelError: self = .init(languageModel: error)
      case let error as PrivateCloudComputeLanguageModel.Error:
        self = .init(privateCloudCompute: error)
      case let error as ClaudeError:
        self = error == .missingCredential ? .missingCredential : .configuration
      case let error as URLError: self = .init(transport: error)
      case is DecodingError: self = .invalidOutput
      default: self = AnthropicWireError(error)?.classification ?? .configuration
    }
  }

  private init(languageModel error: LanguageModelError) {
    switch error {
      case .rateLimited: self = .rateLimited
      case .timeout: self = .timeout
      case .contextSizeExceeded: self = .contextExceeded
      case .refusal, .guardrailViolation: self = .refused
      default: self = .configuration
    }
  }

  private init(privateCloudCompute error: PrivateCloudComputeLanguageModel.Error) {
    switch error {
      case .quotaLimitReached: self = .rateLimited
      case .networkFailure, .serviceUnavailable: self = .network
      @unknown default: self = .configuration
    }
  }

  private init(transport error: URLError) {
    switch error.code {
      case .timedOut: self = .timeout
      case .cancelled: self = .cancelled
      default: self = .network
    }
  }
}

/**
 The Messages API error type carried by the Claude provider's package-scoped API error.

 The provider surfaces HTTP failures it has no framework equivalent for, including every 5xx
 status, as an `APIError` that clients cannot name. Its `Encodable` form is the API's documented
 error object, so the wire `type` identifies the failure.
 */
private struct AnthropicWireError: Decodable {
  let type: String
  let message: String

  var classification: ClassificationError {
    switch type {
      case "api_error": .network
      case "overloaded_error", "rate_limit_error": .rateLimited
      case "authentication_error", "permission_error": .missingCredential
      case "request_too_large": .contextExceeded
      default: .configuration
    }
  }

  init?(_ error: any Error) {
    guard let encodable = error as? any Encodable,
      let data = try? JSONEncoder().encode(encodable),
      let wire = try? JSONDecoder().decode(Self.self, from: data)
    else { return nil }
    self = wire
  }
}
