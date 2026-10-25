import Evaluation
import Foundation
import SpamWiseCore

/// One dry-run pipeline over an isolated temporary store, stopping when a message can't be evaluated.
struct EvaluationRun {
  private static let accountID = "eval"
  private static let maximumMessageBytes = 2_000_000
  private static let messageExtension = "eml"
  let pipeline: Pipeline
  let cache: CachedClassifier
  /// The filtering strength the run decides at.
  let strength: FilteringStrength

  /**
   Runs `body` with a pipeline seeded from `seed` and the selected classifier, removing the
   temporary store afterward.

   The seed's activity, retries, action claims and optional network or OCR evidence are cleared,
   and filtering is set live in dry run at the selected strength, or the seed's when none is
   selected.
   */
  static func with<T>(
    _ options: ClassifierOptions,
    seed: AppState,
    _ body: (Self) async throws -> T
  ) async throws -> T {
    let temporary = FileManager.default.temporaryDirectory.appending(
      path: "SpamWise-eval-\(UUID())"
    )
    defer { try? FileManager.default.removeItem(at: temporary) }
    let store = try Store(url: temporary.appending(path: "state.store"))
    let strength = options.strength ?? seed.settings.strength
    let initial = isolated(seed, strength: strength)
    try await StateRepository.update(store) { $0 = initial }
    let cache = try CachedClassifier(
      directory: URL(filePath: options.cache),
      model: try options.identity,
      underlying: await options.classifier()
    )
    return try await body(
      Self(pipeline: Pipeline(store: store, classifier: cache), cache: cache, strength: strength)
    )
  }

  /// Reads an optional AppState snapshot, or an empty state.
  static func seed(at path: String?) throws -> AppState {
    try path.map {
      try JSONDecoder().decode(AppState.self, from: Data(contentsOf: URL(filePath: $0)))
    } ?? AppState()
  }

  private static func isolated(_ seed: AppState, strength: FilteringStrength) -> AppState {
    var state = seed
    state.settings.strength = strength
    state.settings.paused = false; state.settings.dryRun = true
    var advanced = state.settings.advancedOptions
    advanced.externalEvidence = nil; advanced.imageOCR = false
    state.settings.advancedOptions = advanced
    state.records = []; state.claimedActions = [:]; state.retries = []
    return state
  }

  private static func messageFiles(in directory: URL) -> [URL] {
    guard
      let enumerator = FileManager.default.enumerator(
        at: directory,
        includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
        options: .skipsHiddenFiles
      )
    else { return [] }
    return enumerator.allObjects.compactMap { $0 as? URL }
      .filter { $0.pathExtension.lowercased() == messageExtension }
      .sorted { $0.path < $1.path }
  }

  private static func contents(of file: URL, named name: String) throws -> Data {
    let resolved = file.resolvingSymlinksInPath()
    let properties = try resolved.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
    guard properties.isRegularFile == true else { throw CorpusRunError.notRegularFile(name) }
    guard (properties.fileSize ?? Int.max) <= maximumMessageBytes else {
      throw CorpusRunError.messageTooLarge(file: name, limit: maximumMessageBytes)
    }
    return try Data(contentsOf: resolved)
  }

  /// Evaluates every labeled `.eml` file under `good/`, `junk/` and `graymail/`.
  func corpus(at root: URL) async throws -> [EvaluationObservation] {
    var observations: [EvaluationObservation] = [], originals: [String: String] = [:]
    for truth in EvaluationTruth.allCases {
      for file in Self.messageFiles(in: root.appending(path: truth.rawValue)) {
        let name = String(file.path.dropFirst(root.path.count + 1))
        let raw = try Self.contents(of: file, named: name), hash = stableHash(raw)
        if let original = originals.updateValue(name, forKey: hash) {
          throw CorpusRunError.duplicateMessage(file: name, original: original)
        }
        let record = await pipeline.process(
          .init(identity: .init(accountID: Self.accountID, contentHash: hash), raw: raw),
          forceDryRun: true
        )
        try await requireEvaluated(record, file: name)
        observations.append(
          .init(
            file: name,
            truth: truth,
            partition: LearningSample.partition(for: hash),
            record: record
          )
        )
      }
    }
    guard !observations.isEmpty else { throw CorpusRunError.emptyCorpus(root) }
    return observations
  }

  /// Evaluates retained reviewed messages; truth labels never reach the pipeline.
  func reviewed(_ corpus: ReviewedCorpus) async throws -> [EvaluationObservation] {
    var observations: [EvaluationObservation] = []
    for entry in corpus.entries {
      let name = "reviewed/" + entry.id
      let record = await pipeline.process(
        entry.message,
        identity: .init(accountID: Self.accountID, contentHash: entry.id),
        forceDryRun: true
      )
      try await requireEvaluated(record, file: name)
      observations.append(
        .init(file: name, truth: entry.truth, partition: entry.partition, record: record)
      )
    }
    return observations
  }

  /// Stops the run when a refusal or storage failure left this message unevaluated.
  private func requireEvaluated(_ record: DecisionRecord, file: String) async throws {
    if let refusal = await cache.refusal {
      throw CorpusRunError.stopped(file: file, cause: Diagnostics.describe(refusal))
    }
    switch record.decision.reason {
      case .spendingLimitReached, .storageUnavailable:
        throw CorpusRunError.stopped(
          file: file,
          cause: record.decision.reason.diagnosticDescription
        )
      default: break
    }
  }
}
