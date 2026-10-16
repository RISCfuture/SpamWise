import SwiftUI
import SpamWiseCore
import UniformTypeIdentifiers

struct LearningSettingsView: View {
  let settings: SettingsModel
  let shared: SharedStateModel
  let rules: RulesModel
  let activity: ActivityModel
  @State private var exporting = false
  @State private var exportDocument: RulesDocument?
  @State private var exportStatus: OperationStatus?

  var body: some View {
    Section {
      Toggle(
        "Recognize campaigns you marked as Junk",
        isOn: settings.advancedBinding(\.fingerprints)
      )
      Toggle("Learn from words in corrected mail", isOn: settings.advancedBinding(\.bayes))
      Toggle(
        "Learn which evidence matters most",
        isOn: settings.advancedBinding(\.learnedWeights)
      )
    } header: {
      Text("Learning from corrections")
    } footer: {
      Text(
        """
        SpamWise learns from mail you mark Good or Junk once it has enough of each. Your sender \
        rules always come first.
        """
      )
      .foregroundStyle(.secondary)
    }
    DomainSuggestionsView(shared: shared, rules: rules, activity: activity)
    Section {
      LabeledContent("Reviewed labels", value: shared.state.reviewedLabels.count.formatted())
      Toggle(
        "Retain reviewed text for evaluation export",
        isOn: settings.advancedBinding(\.retainReviewedContent)
      )
      Button("Export reviewed labels…") { exportLabels() }
        .disabled(shared.state.reviewedLabels.isEmpty)
      StatusLabel(status: exportStatus)
    } header: {
      Text("Evaluation data")
    } footer: {
      Text(
        """
        Keeps the text of up to \(RetentionLimits.reviewedLabels) reviewed messages on this Mac \
        for export. Turning this off deletes the kept text; labels and learning remain.
        """
      )
      .foregroundStyle(.secondary)
    }
    .fileExporter(
      isPresented: $exporting,
      document: exportDocument,
      contentType: .json,
      defaultFilename: "SpamWise-reviewed-labels"
    ) {
      exportStatus = ExportResult.status(of: $0, failure: "Reviewed labels could not be exported.")
    }
  }

  private func exportLabels() {
    do {
      exportDocument = RulesDocument(
        data: try JSONEncoder.pretty.encode(shared.state.reviewedLabels)
      )
      exportStatus = nil
      exporting = true
    } catch {
      exportStatus = .failure(OperationFailure(error))
    }
  }
}

private struct DomainSuggestionsView: View {
  let shared: SharedStateModel
  let rules: RulesModel
  let activity: ActivityModel
  @State private var senderCounts: [String: Int] = [:]

  private var suggestions: [PolicySuggestion] {
    PolicyDistiller.suggestions(from: shared.state.corrections, rules: shared.state.rules)
  }

  var body: some View {
    let suggestions = suggestions
    if !suggestions.isEmpty {
      Section("Suggested domain rules") {
        ForEach(suggestions) { suggestion in
          LabeledContent {
            Button(suggestion.label == .inbox ? "Allow domain" : "Block domain") {
              rules.saveSuggestedRule(
                domain: suggestion.domain,
                disposition: suggestion.label == .inbox ? .allow : .block
              )
            }
          } label: {
            Text(suggestion.domain)
            Text("Known senders: \(senderCounts[suggestion.domain, default: 0])")
          }
        }
        OperationStatusView(operation: rules.senderRules)
      }
      .task(id: Set(suggestions.map(\.domain))) {
        senderCounts = await activity.knownSenderCounts(atDomains: Set(suggestions.map(\.domain)))
      }
    }
  }
}

#Preview("Learning") {
  let model = PreviewHelper.model()
  Form {
    LearningSettingsView(
      settings: model.settings,
      shared: model.shared,
      rules: model.rules,
      activity: model.activity
    )
  }.formStyle(.grouped)
}
#Preview("Suggestions") {
  let model = PreviewHelper.model(suggestions: true)
  Form { DomainSuggestionsView(shared: model.shared, rules: model.rules, activity: model.activity) }
    .formStyle(.grouped)
}
