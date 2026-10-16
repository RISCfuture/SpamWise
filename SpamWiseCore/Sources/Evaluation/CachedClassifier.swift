public import Foundation
public import SpamWiseCore

/// Persists validated model responses independently of action policy.
public actor CachedClassifier: Classifier {
  private let directory: URL
  private let model: String
  private let underlying: any Classifier
  /// Responses reused without a provider call during this run.
  public private(set) var hits = 0
  /// Provider calls made during this run.
  public private(set) var misses = 0
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
    misses += 1
    let verdict = try await underlying.classify(input).validated()
    newUsage.input += verdict.usage.input
    newUsage.output += verdict.usage.output
    newUsage.cached += verdict.usage.cached
    newUsage.estimated = newUsage.estimated || verdict.usage.estimated
    try JSONEncoder().encode(verdict).write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    return verdict
  }
}
