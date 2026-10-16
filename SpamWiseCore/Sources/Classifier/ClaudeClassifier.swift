import Foundation
import FoundationModels
import ClaudeForFoundationModels

@Generable private enum GuidedLabel { case inbox, review, junk }
@Generable private struct GuidedVerdict {
  var label: GuidedLabel
  @Guide(description: "Confidence 0 to 100; not a calibrated probability", .range(0...100))
  var confidence: Int
  @Guide(description: "One short sentence explaining the evidence; at most 240 characters")
  var reason: String
}
/// Guided Claude classification with a fresh session and bounded deadline.
public struct ClaudeClassifier: Classifier {
  /// The explicitly selected Claude model identifier.
  public static let modelID = "claude-haiku-5-5"
  private let selectedModel: ClaudeModel
  /// Creates an explicitly selected supported model for evaluation; the app defaults to Haiku 5.5.
  public init(modelID: String, key: @escaping @Sendable () throws -> String) throws {
    switch modelID {
      case "claude-haiku-5-5": selectedModel = .haiku5_5
      case "claude-sonnet-5-5": selectedModel = .sonnet5_5
      case "claude-opus-5-5": selectedModel = .opus5_5
      default: throw ClassificationError.configuration
    }
    self.key = key
  }
  private let key: @Sendable () throws -> String
  /// Creates a ClaudeClassifier with the supplied configuration.
  public init(key: @escaping @Sendable () throws -> String) {
    self.key = key; selectedModel = .haiku5_5
  }
  /// Produces a validated verdict or throws without requesting a mail action.
  public func classify(_ input: ClassificationInput) async throws -> Verdict {
    let credential = try key()
    guard !credential.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw ClassificationError.missingCredential
    }
    let prompt = try PromptBuilder.prompt(input)
    do {
      return try await withDeadline(seconds: input.timeout) {
        let model = ClaudeLanguageModel(
          name: selectedModel,
          auth: .apiKey(credential),
          fixedEffort: .low,
          fallbacks: [],
          timeout: input.timeout
        )
        let session = LanguageModelSession(model: model, instructions: PromptBuilder.instructions)
        let response = try await session.respond(
          to: prompt,
          generating: GuidedVerdict.self,
          options: GenerationOptions(maximumResponseTokens: 1024)
        )
        try Task.checkCancellation()
        let label: MailLabel
        switch response.content.label { case .inbox: label = .inbox;  case .review:
          label = .review
          case .junk: label = .junk
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
            estimated: false
          )
        ).validated()
      }
    } catch is CancellationError { throw ClassificationError.cancelled } catch let error
      as ClassificationError
    { throw error } catch let error as LanguageModelError {
      switch error {
        case .rateLimited: throw ClassificationError.rateLimited
        case .timeout: throw ClassificationError.timeout
        case .contextSizeExceeded: throw ClassificationError.contextExceeded
        case .refusal, .guardrailViolation: throw ClassificationError.refused
        default: throw ClassificationError.configuration
      }
    } catch let error as ClaudeError {
      if case .missingCredential = error { throw ClassificationError.missingCredential }
      throw ClassificationError.configuration
    } catch is URLError { throw ClassificationError.network } catch {
      throw ClassificationError.configuration
    }
  }
}
