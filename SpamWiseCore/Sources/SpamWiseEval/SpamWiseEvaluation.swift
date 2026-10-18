import ArgumentParser

/// Offline and explicitly authorized live evaluation of SpamWise against human-labeled mail.
@main struct SpamWiseEvaluation: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "spamwise-eval",
    abstract: "Evaluates SpamWise against independently labeled mail.",
    discussion: """
      Every run is a dry run: no Mail action is requested. Live calls require SPAMWISE_LIVE_API=1 \
      and the selected provider’s API key environment variable; paid models also require \
      --budget-store, where each call reserves a conservative bound first.
      """,
    subcommands: [
      CorpusCommand.self, ReviewedCommand.self, ExportCommand.self, CompareCommand.self,
      ThreatReportCommand.self
    ]
  )
}
