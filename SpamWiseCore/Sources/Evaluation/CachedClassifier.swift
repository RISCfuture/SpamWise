public import Foundation
public import SpamWiseCore

/// Persists validated model responses independently of action policy.
public actor CachedClassifier: Classifier {
  private let directory: URL
  private let model: String
  private let underlying: any Classifier
  /// Responses reused without a provider call during this run.
  public private(set) var hits = 0
  /// Requests that reached the underlying classifier, whether or not they returned a verdict.
  public private(set) var providerCalls = 0
  /// Requests that reached the underlying classifier but produced no valid verdict.
  public private(set) var failedProviderCalls = 0
  /**
   The first refusal that left a message unevaluated without reaching the provider: a budget or
   storage failure, or an evaluation input error such as a missing mock response.

   Metrics over the remaining cohort would describe a different corpus, so callers stop the run.
   */
  public private(set) var refusal: (any Error)?
  /// Newly incurred usage, excluding previously cached responses.
  public private(set) var newUsage = TokenUsage(estimated: false)

  /// Creates a private cache directory for the explicitly selected backend.
  public init(directory: URL, model: String, underlying: any Classifier) throws {
    self.directory = directory
    self.model = model
    self.underlying = underlying
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
  }

  private static func refusesEvaluation(_ error: any Error) -> Bool {
    error is any BudgetFailure || error is any StorageFailure || error is any CorpusEvaluationError
  }

  /// Reuses only responses with matching content, effective prompt, model, and schema identities.
  public func classify(_ input: ClassificationInput) async throws -> Verdict {
    let components = [
      input.message.hash, PromptBuilder.instructions, try PromptBuilder.prompt(input),
      model, PromptBuilder.schemaID
    ]
    let key = stableHash(try JSONEncoder().encode(components))
    let url = directory.appending(path: key + ".json")
    if let data = try? Data(contentsOf: url),
      let verdict = try? JSONDecoder().decode(Verdict.self, from: data).validated()
    {
      hits += 1
      return verdict
    }
    let verdict = try await classifyUncached(input)
    newUsage.input += verdict.usage.input
    newUsage.output += verdict.usage.output
    newUsage.cached += verdict.usage.cached
    newUsage.estimated = newUsage.estimated || verdict.usage.estimated
    try JSONEncoder().encode(verdict).write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    return verdict
  }

  private func classifyUncached(_ input: ClassificationInput) async throws -> Verdict {
    let response: Verdict
    do { response = try await underlying.classify(input) } catch {
      recordFailure(error)
      throw error
    }
    providerCalls += 1
    do { return try response.validated() } catch {
      failedProviderCalls += 1
      throw error
    }
  }

  private func recordFailure(_ error: any Error) {
    if Self.refusesEvaluation(error) {
      refusal = refusal ?? error
    } else {
      providerCalls += 1; failedProviderCalls += 1
    }
  }
}
