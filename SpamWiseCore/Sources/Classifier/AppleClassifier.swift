import Foundation
import FoundationModels

/// Explicit Apple execution location; availability never selects another backend.
public enum AppleModelBackend: String, Codable, CaseIterable, Sendable {
  /// Executes using the available model on this Mac.
  case onDevice
  /// Executes using the explicitly authorized Private Cloud Compute model.
  case privateCloudCompute

  /// Model identity recorded with usage and cache keys for this execution location.
  public var model: ModelIdentifier {
    switch self {
      case .onDevice: .appleOnDevice
      case .privateCloudCompute: .applePrivateCloudCompute
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
      generating: GuidedVerdict.self,
      options: GenerationOptions(maximumResponseTokens: limit)
    )
    try Task.checkCancellation()
    return try Verdict(guided: response.content, session: session, model: backend.model)
  }
  /// Produces a validated result within fifteen seconds; availability, quota and refusal errors fail open.
  public func classify(_ input: ClassificationInput) async throws -> Verdict {
    let prompt = try PromptBuilder.prompt(input)
    do {
      return try await withDeadline(
        seconds: min(
          ClassificationLimits.timeoutRange.upperBound,
          max(ClassificationLimits.timeoutRange.lowerBound, input.timeout)
        )
      ) {
        try await generate(
          backend,
          PromptBuilder.instructions,
          prompt,
          ClassificationLimits.maximumResponseTokens
        ).validated()
      }
    } catch { throw ClassificationError(mapping: error) }
  }
}
