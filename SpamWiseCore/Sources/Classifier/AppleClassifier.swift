import Foundation
import FoundationModels

/// Explicit Apple execution location; availability never selects another backend.
public enum AppleModelBackend: String, Codable, CaseIterable, Sendable {
  /// Executes using the available model on this Mac.
  case onDevice = "onDevice"
  /// Executes using the explicitly authorized Private Cloud Compute model.
  case privateCloudCompute = "privateCloudCompute"

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

  private static let maximumContextAttempts = 3
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
        try await requireContext(
          for: prompt,
          instructions: instructions,
          responseTokens: limit,
          in: model
        )
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

  /**
   Throws ``LanguageModelError/contextSizeExceeded(_:)`` without generating when the prompt
   doesn't fit the context the instructions, schema and response leave for it.

   The error compares the prompt's own tokens with the room left for it, so a shorter prompt can
   be chosen in proportion.
   */
  private static func requireContext(
    for prompt: String,
    instructions: String,
    responseTokens: Int,
    in model: SystemLanguageModel
  ) async throws {
    let fixedTokens =
      try await model.tokenCount(for: Instructions(instructions))
      + model.tokenCount(for: GuidedVerdict.generationSchema) + responseTokens
    let promptTokens = try await model.tokenCount(for: prompt)
    let room = max(0, model.contextSize - fixedTokens)
    guard promptTokens > room else { return }
    throw LanguageModelError.contextSizeExceeded(
      .init(
        contextSize: room,
        tokenCount: promptTokens,
        debugDescription: "The prompt exceeds the context left for it."
      )
    )
  }

  /// The largest shorter prompt, in bytes, expected to fit a context that `prompt` exceeded.
  private static func shortenedBytes(
    _ prompt: String,
    exceeding exceeded: LanguageModelError.ContextSizeExceeded
  ) -> Int {
    let bytes = prompt.utf8.count
    let scale = Double(exceeded.contextSize) / Double(max(1, exceeded.tokenCount))
    return min(bytes - 1, Int(Double(bytes) * scale))
  }

  /**
   Generates a validated verdict, shortening a prompt that exceeds the model's context in
   proportion and trying again, up to three attempts in all.

   - Throws: ``ClassificationError/evidenceExceedsPrompt`` when no shorter prompt remains.
   */
  private static func fittedVerdict(
    _ input: ClassificationInput,
    backend: AppleModelBackend,
    generate: Generate
  ) async throws -> Verdict {
    var candidates = PromptBuilder.Candidates(input)
    guard var prompt = try candidates.next() else {
      throw ClassificationError.evidenceExceedsPrompt
    }
    for _ in 1..<maximumContextAttempts {
      do {
        return try await validatedVerdict(prompt, backend: backend, generate: generate)
      } catch let LanguageModelError.contextSizeExceeded(exceeded) {
        let maximumBytes = shortenedBytes(prompt, exceeding: exceeded)
        guard let shorter = try candidates.next(maximumBytes: maximumBytes) else {
          throw ClassificationError.evidenceExceedsPrompt
        }
        prompt = shorter
      }
    }
    return try await validatedVerdict(prompt, backend: backend, generate: generate)
  }

  private static func validatedVerdict(
    _ prompt: String,
    backend: AppleModelBackend,
    generate: Generate
  ) async throws -> Verdict {
    try await generate(
      backend,
      PromptBuilder.instructions,
      prompt,
      ClassificationLimits.maximumResponseTokens
    ).validated()
  }

  /**
   Produces a validated result within fifteen seconds; availability, quota and refusal errors
   fail open.

   A prompt that exceeds the model's context is shortened to fit when it can be; otherwise this
   throws ``ClassificationError/evidenceExceedsPrompt``.
   */
  public func classify(_ input: ClassificationInput) async throws -> Verdict {
    do {
      return try await withDeadline(
        seconds: min(
          ClassificationLimits.timeoutRange.upperBound,
          max(ClassificationLimits.timeoutRange.lowerBound, input.timeout)
        )
      ) { [backend, generate] in
        try await Self.fittedVerdict(input, backend: backend, generate: generate)
      }
    } catch { throw ClassificationError(mapping: error) }
  }
}
