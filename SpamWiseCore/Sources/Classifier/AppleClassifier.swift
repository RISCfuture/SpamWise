import Foundation
import FoundationModels

/// Explicit Apple execution location; availability never selects another backend.
public enum AppleModelBackend: String, Codable, CaseIterable, Sendable {
  case onDevice, privateCloudCompute

  /// Stable cache and usage identity for the selected execution location.
  public var modelID: String {
    switch self {
      case .onDevice: "apple-on-device"
      case .privateCloudCompute: "apple-private-cloud-compute"
    }
  }
}

/// Fresh guided Foundation Models sessions, with no automatic location fallback.
public struct AppleClassifier: Classifier {
  /// Injectable generation boundary preserving the chosen backend and bounded session configuration.
  public typealias Generate =
    @Sendable (AppleModelBackend, String, String, Int) async throws -> Verdict
  private let backend: AppleModelBackend
  private let generate: Generate

  /// Creates an Apple backend. PCC requires Apple's managed `com.apple.developer.private-cloud-compute` entitlement.
  public init(backend: AppleModelBackend, generate: Generate? = nil) {
    self.backend = backend; self.generate = generate ?? Self.generate
  }

  /// Produces a validated result within fifteen seconds; availability, quota and refusal errors fail open.
  public func classify(_ input: ClassificationInput) async throws -> Verdict {
    let prompt = try PromptBuilder.prompt(input)
    do {
      return try await withDeadline(seconds: min(15, max(0.01, input.timeout))) {
        try await generate(backend, PromptBuilder.instructions, prompt, 1024).validated()
      }
    } catch is CancellationError { throw ClassificationError.cancelled } catch let error
      as ClassificationError
    { throw error } catch let error as LanguageModelError {
      switch error {
        case .contextSizeExceeded: throw ClassificationError.contextExceeded
        case .rateLimited: throw ClassificationError.rateLimited
        case .guardrailViolation, .refusal: throw ClassificationError.refused
        case .timeout: throw ClassificationError.timeout
        default: throw ClassificationError.configuration
      }
    } catch let error as PrivateCloudComputeLanguageModel.Error {
      switch error {
        case .quotaLimitReached: throw ClassificationError.rateLimited
        case .networkFailure, .serviceUnavailable: throw ClassificationError.network
        @unknown default: throw ClassificationError.configuration
      }
    } catch { throw ClassificationError.configuration }
  }

  private static func generate(
    backend: AppleModelBackend,
    instructions: String,
    prompt: String,
    limit: Int
  ) async throws -> Verdict {
    let session: LanguageModelSession
    switch backend {
      case .onDevice:
        let model = SystemLanguageModel.default
        guard model.isAvailable else { throw ClassificationError.configuration }
        session = LanguageModelSession(model: model, instructions: instructions)
      case .privateCloudCompute:
        let model = PrivateCloudComputeLanguageModel()
        guard model.isAvailable else { throw ClassificationError.configuration }
        session = LanguageModelSession(model: model, instructions: instructions)
    }
    let response = try await session.respond(
      to: prompt,
      generating: AppleGuidedVerdict.self,
      options: GenerationOptions(maximumResponseTokens: limit)
    )
    try Task.checkCancellation()
    guard let label = MailLabel(rawValue: response.content.label.rawValue),
      response.content.reason.count <= 240
    else {
      throw ClassificationError.invalidOutput
    }
    let usage = session.usage
    return try Verdict(
      label: label,
      confidence: response.content.confidence,
      reason: response.content.reason,
      usage: .init(
        input: usage.input.totalTokenCount,
        output: usage.output.totalTokenCount,
        cached: usage.input.cachedTokenCount,
        estimated: false,
        modelID: backend.modelID,
        pricing: try .rates(for: backend.modelID)
      )
    ).validated()
  }
}

@Generable private enum AppleGuidedLabel: String { case inbox, review, junk }
@Generable private struct AppleGuidedVerdict {
  var label: AppleGuidedLabel
  @Guide(description: "Uncalibrated confidence from 0 through 100", .range(0...100))
  var confidence: Int
  @Guide(description: "One short evidence-grounded sentence, at most 240 characters")
  var reason: String
}
