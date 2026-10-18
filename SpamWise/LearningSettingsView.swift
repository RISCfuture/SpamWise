import SwiftUI
import SpamWiseCore
import UniformTypeIdentifiers

struct LearningSettingsView: View {
  let settings: SettingsModel
  let shared: SharedStateModel
  let rules: RulesModel
  let activity: ActivityModel
  @State private var exporting = false
  @State private var exportStatus: OperationStatus?

  var body: some View {
    Section {
      DisclosureGroup("Learning from corrections") {
        Toggle("Match explicitly junked campaigns", isOn: settings.advancedBinding(\.fingerprints))
        Toggle("Use Bayes as supporting evidence", isOn: settings.advancedBinding(\.bayes))
        Toggle("Use learned evidence weights", isOn: settings.advancedBinding(\.learnedWeights))
        Text(
          "Learning needs reviewed good and junk examples. Your sender rules always take precedence."
        )
        .foregroundStyle(.secondary)
        DomainSuggestionsView(shared: shared, rules: rules, activity: activity)
      }
    }
    Section {
      DisclosureGroup("Evaluation data") {
        LabeledContent(
          "Reviewed labels",
          value: shared.state.reviewedLabels.count.formatted()
        )
        Toggle(
          "Retain reviewed text for evaluation export",
          isOn: settings.advancedBinding(\.retainReviewedContent)
        )
        Text(
          """
          Retains up to 500 bounded reviewed messages locally. Turning this off removes previously \
          retained text; labels and derived learning remain.
          """
        )
        .foregroundStyle(.secondary)
        Button("Export reviewed labels…") { exporting = true }
          .disabled(shared.state.reviewedLabels.isEmpty)
        StatusLabel(status: exportStatus)
      }
    }
    .fileExporter(
      isPresented: $exporting,
      document: RulesDocument(
        data: (try? JSONEncoder.pretty.encode(shared.state.reviewedLabels)) ?? Data()
      ),
      contentType: .json,
      defaultFilename: "SpamWise-reviewed-labels"
    ) {
      exportStatus = ExportResult.status(of: $0, failure: "Reviewed labels could not be exported.")
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
      Text("Suggested domain preferences").font(.headline)
        .frame(maxWidth: .infinity, alignment: .leading)
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
          Text(
            "Known senders: \(senderCounts[suggestion.domain, default: 0], format: .number)"
          )
        }
      }
      OperationStatusView(operation: rules.senderRules)
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
