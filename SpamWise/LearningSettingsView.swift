import SwiftUI
import SpamWiseCore

/// Learning from corrections, kept reviewed text and suggested domain rules.
struct LearningSettingsView: View {
  let settings: SettingsModel
  let shared: SharedStateModel
  let rules: RulesModel
  let activity: ActivityModel

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
      Toggle(
        "Keep text of reviewed messages",
        isOn: settings.advancedBinding(\.retainReviewedContent)
      )
    } header: {
      Text("Learning from corrections")
    } footer: {
      Text(
        """
        SpamWise learns from mail you mark Good or Junk once it has enough of each. Your sender \
        rules always come first. Keeping text saves up to \(RetentionLimits.reviewedLabels) \
        reviewed messages on this Mac, so Reviewed Messages can show and export them. Turning it \
        off deletes the kept text; labels and learning remain.
        """
      )
      .foregroundStyle(.secondary)
    }
    DomainSuggestionsView(shared: shared, rules: rules, activity: activity)
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
            Button(suggestion.label == .inbox ? "Allow Domain" : "Block Domain") {
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
