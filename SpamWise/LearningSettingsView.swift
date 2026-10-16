import SwiftUI
import SpamWiseCore
import UniformTypeIdentifiers

struct LearningSettingsView: View {
  @Bindable var model: AppModel
  @State private var exporting = false
  var body: some View {
    Section("Learning from corrections") {
      Toggle("Retrieve similar corrections", isOn: model.advancedBinding(\.retrieveExamples))
      Toggle("Match explicitly junked campaigns", isOn: model.advancedBinding(\.fingerprints))
      Toggle("Use Bayes as supporting evidence", isOn: model.advancedBinding(\.bayes))
      Toggle("Use learned evidence weights", isOn: model.advancedBinding(\.learnedWeights))
      Text(
        """
        Statistical scores remain uncalibrated and require reviewed examples of both good and junk \
        mail. Address and domain rules take precedence.
        """
      ).font(.caption)
      Text("Reviewed labels: \(model.state.reviewedLabels?.count ?? 0)")
      Toggle(
        "Retain reviewed text for evaluation export",
        isOn: model.advancedBinding(\.retainReviewedContent)
      )
      Text(
        """
        Retains up to 500 bounded reviewed messages locally. Turning this off removes previously \
        retained text; labels and derived learning remain.
        """
      ).font(.caption)
      Button("Export reviewed labels…") { exporting = true }
        .disabled((model.state.reviewedLabels ?? []).isEmpty)
    }
    Section("Suggested domain preferences") {
      let suggestions = PolicyDistiller.suggestions(from: model.state.corrections)
      if suggestions.isEmpty {
        Text("Suggestions appear after consistent corrections across multiple senders on a domain.")
          .font(.caption)
      }
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
      Text("Suggestions never change your rules until you apply them.").font(.caption)
    }
    Section("Weekly Review digest") {
      Toggle("Show a weekly Review digest", isOn: model.advancedBinding(\.weeklyDigest))
      Button("Show Review digest") { model.showDigest = true }
      Text("A local summary of unresolved Review items from the last seven days. No email is sent.")
        .font(.caption)
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

struct ReviewDigestView: View {
  @Bindable var model: AppModel
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Weekly Review digest").font(.title2.bold())
      let records = ReviewDigest(state: model.state).records
      if records.isEmpty { Text("No unresolved Review items in the last seven days.") }
      List(records) { record in
        VStack(alignment: .leading) {
          Text(record.subject).font(.headline)
          Text(record.sender)
          Text(record.decision.reason).foregroundStyle(.secondary)
        }
      }
      Button("Done") { model.showDigest = false }.keyboardShortcut(.defaultAction)
    }.padding(24).frame(width: 600, height: 450)
  }
}

#Preview { Form { LearningSettingsView(model: PreviewHelper.model()) } }
#Preview { ReviewDigestView(model: PreviewHelper.model()) }
