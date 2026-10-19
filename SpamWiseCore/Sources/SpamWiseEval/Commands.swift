import ArgumentParser
import Evaluation
import Foundation
import MailIntegration
import SpamWiseCore

/// Where a JSON report goes: standard output, and optionally a file.
struct ReportOutput: ParsableArguments {
  @Option(help: "Also write the JSON report to this path.")
  var output: String?

  /// Prints `report` as sorted, indented JSON, writing it to ``output`` first when set.
  func publish(_ report: some Encodable) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let text = try encoder.encodeText(report)
    if let output { try Data(text.utf8).write(to: URL(filePath: output), options: .atomic) }
    print(text)
  }
}

/// Evaluates a directory corpus of independently labeled `.eml` files.
struct CorpusCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "corpus",
    abstract: "Evaluates labeled .eml files in good/, junk/ and optional graymail/.",
    discussion: """
      Duplicate message bytes are rejected. Reports contain filenames and reasons, never bodies. \
      With eval/fixtures, pass --state eval/fixture-state.json to seed the order-confirmation \
      sender’s receipt history, and --mock-responses eval/mock-responses.json for the offline \
      plumbing check.
      """
  )

  @Argument(help: "Corpus directory.")
  var directory: String

  @Option(help: "AppState JSON supplying rules, contacts and history under account ID eval.")
  var state: String?

  @OptionGroup var classifier: ClassifierOptions
  @OptionGroup var report: ReportOutput

  func run() async throws {
    try await Diagnostics.reporting {
      let root = URL(filePath: directory, directoryHint: .isDirectory)
      try await EvaluationRun.with(classifier, seed: EvaluationRun.seed(at: state)) { run in
        let observations = try await run.corpus(at: root)
        try report.publish(
          await RunReport(options: classifier, observations: observations, cache: run.cache)
        )
      }
    }
  }
}

/// Evaluates retained reviewed labels exported by the app.
struct ReviewedCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "reviewed",
    abstract: "Evaluates reviewed labels exported by SpamWise.",
    discussion: """
      Labels never enter model prompts. Missing retained text is reported, not evaluated as empty \
      mail. Use --partition all to select thresholds on training labels and validate them on \
      held-out labels.
      """
  )

  @Argument(help: "Exported reviewed-labels JSON.")
  var labels: String

  @Option(help: "Content partition to evaluate.")
  var partition: ReviewedCorpusPartition = .heldOut

  @Option(help: "AppState JSON for exploratory training-partition runs only.")
  var state: String?

  @OptionGroup var classifier: ClassifierOptions
  @OptionGroup var report: ReportOutput

  func validate() throws {
    guard state == nil || partition == .training else {
      throw ValidationError(
        String(localized: "--state is allowed only with --partition training.", bundle: .module)
      )
    }
  }

  func run() async throws {
    try await Diagnostics.reporting {
      let corpus = try ReviewedCorpus(url: URL(filePath: labels), partition: partition)
      try await EvaluationRun.with(classifier, seed: EvaluationRun.seed(at: state)) { run in
        let observations = try await run.reviewed(corpus)
        try report.publish(
          await RunReport(
            options: classifier,
            observations: observations,
            cache: run.cache,
            reviewed: corpus.summary
          )
        )
      }
    }
  }
}

/// Exports unlabeled Mail messages for independent human labeling.
struct ExportCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "export",
    abstract: "Exports recent messages from one mailbox role for human labeling.",
    discussion: "Mailbox placement is not ground truth; label every exported message yourself."
  )
  private static let limits = 1...1000

  @Argument(help: "Mailbox role to export.")
  var role: MailboxRole

  @Option(help: "Directory that receives the exported .eml files.")
  var destination: String

  @Option(help: "Most recent messages to export.")
  var limit = 500

  func validate() throws {
    guard Self.limits.contains(limit) else {
      throw ValidationError(
        String(
          localized:
            "--limit must be from \(Self.limits.lowerBound, format: .number) to \(Self.limits.upperBound, format: .number).",
          bundle: .module
        )
      )
    }
  }

  func run() async throws {
    try await Diagnostics.reporting {
      let adapter = await AppleMailAdapter(runner: SystemAppleEventRunner())
      let count = try await adapter.export(
        role: role,
        to: URL(filePath: destination),
        limit: limit
      )
      print(
        String(
          localized:
            "Exported \(count, format: .number) messages. Assign human labels before evaluating.",
          bundle: .module
        )
      )
    }
  }
}

/// Compares frozen system runs over one human-reviewed holdout.
struct CompareCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "compare",
    abstract: "Computes paired metrics from a frozen comparison manifest."
  )

  @Argument(help: "Frozen comparison manifest JSON.")
  var manifest: String

  @OptionGroup var report: ReportOutput

  func run() async throws {
    try await Diagnostics.reporting {
      try report.publish(ComparisonReport(contentsOf: URL(filePath: manifest)))
    }
  }
}

/// Reports objective threat-detection metrics from labeled observations.
struct ThreatReportCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "threat-report",
    abstract: "Computes per-objective threat metrics from labeled observations."
  )

  @Argument(help: "Objective observations JSON.")
  var observations: String

  @OptionGroup var report: ReportOutput

  func run() async throws {
    try await Diagnostics.reporting {
      try report.publish(ThreatEvaluationReport(contentsOf: URL(filePath: observations)))
    }
  }
}
