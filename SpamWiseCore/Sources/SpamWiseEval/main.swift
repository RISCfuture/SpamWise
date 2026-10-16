import Foundation
import SpamWiseCore
import MailIntegration
import Evaluation

@main struct SpamWiseEvaluation {
  static func main() async {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments.isEmpty || arguments == ["--help"] { print(Options.usage); return }
    do {
      let options = try Options(arguments)
      if options.values["export"] != nil {
        try await export(options)
      } else {
        try await evaluate(options)
      }
    } catch {
      let message =
        (error as? EvaluationError)?.localizedDescription
        ?? (error as? ClassificationError)?.localizedDescription
        ?? "Evaluation failed. Check paths, input format, and permissions."
      FileHandle.standardError.write(Data((message + "\n").utf8))
      exit(1)
    }
  }
  private static func export(_ options: Options) async throws {
    let role: String
    switch try options.required("export") {
      case "inbox": role = "inbox"
      case "junk": role = "junk mailbox"
      case "sent": role = "sent mailbox"
      default: throw EvaluationError.arguments
    }
    guard let limit = Int(options.values["limit"] ?? "500"), (1...1000).contains(limit) else {
      throw EvaluationError.arguments
    }
    let adapter = await AppleMailAdapter(runner: SystemAppleEventRunner())
    let count = try await adapter.export(
      role: role,
      to: URL(filePath: options.required("destination")),
      limit: limit
    )
    print("Exported \(count) messages. Assign human labels before evaluating.")
  }
  private static func classifier(_ options: Options) throws -> any Classifier {
    if options.model == "mock" {
      if let path = options.values["mock-responses"] {
        let responses = try JSONDecoder().decode(
          [String: Verdict].self,
          from: Data(contentsOf: URL(filePath: path))
        )
        return MockClassifier { input in
          guard let verdict = responses[input.message.hash] else {
            throw EvaluationError.missingMock
          }
          return verdict
        }
      }
      return MockClassifier(
        verdict: .init(label: .review, confidence: 0, reason: "Offline mock: no predictive model")
      )
    }
    guard ProcessInfo.processInfo.environment["SPAMWISE_LIVE_API"] == "1" else {
      throw EvaluationError.liveDisabled
    }
    guard let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !key.isEmpty else {
      throw EvaluationError.missingKey
    }
    return try ClaudeClassifier(modelID: options.model, key: { key })
  }
  private static func evaluate(_ options: Options) async throws {
    let root = URL(filePath: try options.required("input"), directoryHint: .isDirectory)
    let cache = try CachedClassifier(
      directory: URL(filePath: options.values["cache"] ?? ".spamwise-eval-cache"),
      model: options.model + (try mockIdentity(options)),
      underlying: classifier(options)
    )
    let temporary = FileManager.default.temporaryDirectory.appending(
      path: "SpamWise-eval-\(UUID())"
    )
    defer { try? FileManager.default.removeItem(at: temporary) }
    let store = try Store(url: temporary.appending(path: "state.store"))
    var seed =
      try options.values["state"].map {
        try JSONDecoder().decode(AppState.self, from: Data(contentsOf: URL(filePath: $0)))
      } ?? AppState()
    seed.settings.strength = try options.strength
    seed.settings.paused = false; seed.settings.dryRun = true
    seed.records = []; seed.claimedActions = [:]; seed.retries = []
    let initial = seed
    try await StateRepository.update(store) { $0 = initial }
    let pipeline = Pipeline(store: store, classifier: cache)
    let observations = try await runCorpus(root, pipeline: pipeline)
    let report = EvaluationReport(observations: observations)
    let modelObservations = observations.map { row -> EvaluationObservation in
      var row = row; row.label = row.modelLabel; return row
    }
    let output = try await RunReport(
      options: options,
      report: report,
      raw: modelObservations,
      cache: cache
    )
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(output)
    if let path = options.values["output"] {
      try data.write(to: URL(filePath: path), options: .atomic)
    }
    print(String(decoding: data, as: UTF8.self))
  }
  private static func mockIdentity(_ options: Options) throws -> String {
    guard let path = options.values["mock-responses"] else { return "" }
    return ":" + stableHash(try Data(contentsOf: URL(filePath: path)))
  }
  private static func runCorpus(_ root: URL, pipeline: Pipeline) async throws
    -> [EvaluationObservation]
  {
    var observations: [EvaluationObservation] = [], hashes: Set<String> = []
    for truth in EvaluationTruth.allCases {
      let directory = root.appending(path: truth.rawValue)
      guard
        let enumerator = FileManager.default.enumerator(
          at: directory,
          includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
          options: .skipsHiddenFiles
        )
      else { continue }
      let files = enumerator.allObjects.compactMap { $0 as? URL }.filter {
        $0.pathExtension.lowercased() == "eml"
      }.sorted { $0.path < $1.path }
      for file in files {
        let properties = try file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard properties.isRegularFile == true, (properties.fileSize ?? Int.max) <= 2_000_000 else {
          throw EvaluationError.oversizedFile
        }
        let raw = try Data(contentsOf: file), hash = stableHash(raw)
        guard hashes.insert(hash).inserted else { throw EvaluationError.duplicateMessage }
        let result = await pipeline.process(
          .init(identity: .init(accountID: "eval", contentHash: hash), raw: raw),
          forceDryRun: true
        )
        observations.append(
          .init(
            file: String(file.path.dropFirst(root.path.count + 1)),
            truth: truth,
            label: result.decision.label,
            confidence: result.verdict?.confidence,
            path: result.path,
            reason: result.decision.reason,
            modelLabel: result.verdict?.label
          )
        )
      }
    }
    guard !observations.isEmpty else { throw EvaluationError.emptyCorpus }
    return observations
  }
}
