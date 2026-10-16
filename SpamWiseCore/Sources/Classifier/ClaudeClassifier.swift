import Foundation
import FoundationModels
import ClaudeForFoundationModels

/// Guided Claude classification with a fresh session and bounded deadline.
public struct ClaudeClassifier: Classifier {
  private let model: ModelIdentifier
  private let claudeModel: ClaudeModel
  private let key: @Sendable () throws -> String
  private let baseURL: URL

  /// Creates a classifier for an explicitly selected Claude model.
  public init(
    model: ModelIdentifier = ModelBackend.claude.defaultModel,
    key: @escaping @Sendable () throws -> String
  ) {
    self.init(model: model, key: key, baseURL: ClaudeLanguageModel.defaultBaseURL)
  }

  init(model: ModelIdentifier, key: @escaping @Sendable () throws -> String, baseURL: URL) {
    guard let claudeModel = model.claudeModel else {
      preconditionFailure("\(model.rawValue) is not a Claude model")
    }
    self.model = model; self.claudeModel = claudeModel; self.key = key; self.baseURL = baseURL
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
        let session = LanguageModelSession(
          model: languageModel(credential: credential, timeout: input.timeout),
          instructions: PromptBuilder.instructions
        )
        let response = try await session.respond(
          to: prompt,
          generating: GuidedVerdict.self,
          options: GenerationOptions(
            maximumResponseTokens: ClassificationLimits.maximumResponseTokens
          )
        )
        try Task.checkCancellation()
        return try Verdict(guided: response.content, session: session, model: model)
      }
    } catch { throw ClassificationError(mapping: error) }
  }

  private func languageModel(credential: String, timeout: TimeInterval) -> ClaudeLanguageModel {
    ClaudeLanguageModel(
      name: claudeModel,
      auth: .apiKey(credential),
      fixedEffort: .low,
      fallbacks: [],
      baseURL: baseURL,
      timeout: timeout
    )
  }
}
