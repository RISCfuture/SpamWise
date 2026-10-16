import SwiftUI
import SpamWiseCore
import UniformTypeIdentifiers

struct LearningSettingsView: View {
  @Bindable var model: AppModel
  @State private var exporting = false

  var body: some View {
    Section {
      DisclosureGroup("Learning from corrections") {
        Toggle("Retrieve similar corrections", isOn: model.advancedBinding(\.retrieveExamples))
        Toggle("Match explicitly junked campaigns", isOn: model.advancedBinding(\.fingerprints))
        Toggle("Use Bayes as supporting evidence", isOn: model.advancedBinding(\.bayes))
        Toggle("Use learned evidence weights", isOn: model.advancedBinding(\.learnedWeights))
        Text(
          "Learning needs reviewed good and junk examples. Your sender rules always take precedence."
        )
        .foregroundStyle(.secondary)
        DomainSuggestionsView(model: model)
      }
    }
    Section {
      DisclosureGroup("Evaluation data") {
        LabeledContent(
          "Reviewed labels",
          value: (model.state.reviewedLabels?.count ?? 0).formatted()
        )
        Toggle(
          "Retain reviewed text for evaluation export",
          isOn: model.advancedBinding(\.retainReviewedContent)
        )
        Text(
          """
          Retains up to 500 bounded reviewed messages locally. Turning this off removes previously \
          retained text; labels and derived learning remain.
          """
        )
        .foregroundStyle(.secondary)
        Button("Export reviewed labels…") { exporting = true }
          .disabled((model.state.reviewedLabels ?? []).isEmpty)
      }
    }
    .fileExporter(
      isPresented: $exporting,
      document: RulesDocument(
        data: (try? JSONEncoder.pretty.encode(model.state.reviewedLabels ?? [])) ?? Data()
      ),
      contentType: .json,
      defaultFilename: "SpamWise-reviewed-labels"
    ) { result in
      if case .failure = result {
        model.status = String(localized: "Reviewed labels could not be exported.")
      }
    }
  }
}

private struct DomainSuggestionsView: View {
  let model: AppModel
  private var suggestions: [PolicySuggestion] {
    PolicyDistiller.suggestions(from: model.state.corrections)
  }

  var body: some View {
    if !suggestions.isEmpty {
      Text("Suggested domain preferences").font(.headline)
        .frame(maxWidth: .infinity, alignment: .leading)
      ForEach(suggestions) { suggestion in
        LabeledContent(suggestion.domain) {
          Button(suggestion.label == .inbox ? "Allow domain" : "Block domain") {
            model.saveRule(
              scope: .domain,
              value: suggestion.domain,
              disposition: suggestion.label == .inbox ? .allow : .block
            )
          }
        }
      }
    }
  }
}

#Preview("Learning") {
  Form { LearningSettingsView(model: PreviewHelper.model()) }.formStyle(.grouped)
}
#Preview("Suggestions") {
  Form { DomainSuggestionsView(model: PreviewHelper.model(suggestions: true)) }
    .formStyle(.grouped)
}
