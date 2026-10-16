import SwiftUI
import SpamWiseCore

struct SettingsView: View {
  @Bindable var model: AppModel
  func binding<T: Sendable>(_ key: any WritableKeyPath<SpamWiseCore.Settings, T> & Sendable)
    -> Binding<
      T
    >
  {
    Binding(
      get: { model.state.settings[keyPath: key] },
      set: { value in
        model.setSetting(key, to: value)
      }
    )
  }
  var body: some View {
    TabView {
      Form {
        Section("Filtering") {
          Picker("Filtering strength", selection: binding(\.strength)) {
            ForEach(FilteringStrength.allCases, id: \.self) { strength in
              Text(strength.rawValue.capitalized).tag(strength)
            }
          }
          Text(
            """
            Uncalibrated thresholds: Conservative 99%, Balanced 95%, Aggressive 90%. Model \
            confidence is not a probability.
            """
          ).font(.caption).foregroundStyle(.secondary)
          Picker("Review treatment", selection: binding(\.review)) {
            Text("Orange flag (keep in Inbox)").tag(ReviewTreatment.orangeFlag)
            Text("Orange background (keep in Inbox)").tag(ReviewTreatment.orangeBackground)
          }
          Toggle("Dry run — do not change mail", isOn: binding(\.dryRun)).disabled(
            model.state.settings.validatedAccounts.isEmpty
          )
          if model.state.settings.validatedAccounts.isEmpty {
            Text("Complete a disposable-message action test before disabling dry run.").font(
              .caption
            )
          }
          Toggle("Pause filtering", isOn: binding(\.paused))
          HStack {
            Button("Show setup") { model.showSetup = true }; HelpButton(page: "filtering-strength")
          }
        }
        Section("Mail") { MailConnectionView(model: model) }
      }.formStyle(.grouped).tabItem { Label("General", systemImage: "gearshape") }
      PolicyView(model: model).tabItem { Label("Preferences", systemImage: "text.alignleft") }
      Form {
        KeyEntryView(model: model)
        LabeledContent(
          "Month-to-date estimated API cost",
          value: model.monthCost.formatted(.currency(code: "USD"))
        )
        Text(
          """
          Token counts are measured when the provider exposes them. Dollar costs are estimates; \
          cache-write premiums may differ.
          """
        ).font(.caption)
        HelpButton(page: "what-data-is-sent")
      }.formStyle(.grouped).tabItem { Label("Account", systemImage: "key") }
      Form {
        Section("Context limits") {
          Stepper(
            "Recent corrections: \(model.state.settings.correctionLimit)",
            value: binding(\.correctionLimit),
            in: 0...100,
            step: 5
          )
          Stepper(
            "Body budget: ~\(model.state.settings.bodyTokenBudget) tokens",
            value: binding(\.bodyTokenBudget),
            in: 100...4000,
            step: 100
          )
          Text(
            "Body length uses a four-characters-per-token estimate. Quoted reply chains and attachments are omitted."
          ).font(.caption)
        }
        Section("Learned rules (read only)") {
          if model.state.rules.isEmpty {
            Text("Correct a message in Activity to create a rule.").foregroundStyle(.secondary)
          }
          ForEach(model.state.rules) { rule in
            LabeledContent("\(rule.scope.rawValue): \(rule.value)") {
              Text(rule.disposition.rawValue.capitalized).accessibilityIdentifier(
                "settings.rule.\(rule.scope.rawValue).\(rule.value)"
              )
            }
          }
        }
        Section("Integration") {
          LabeledContent("Incoming route", value: model.state.settings.route.rawValue)
          Text(
            "MailKit remains dry-run-only pending signed timing and account identity validation."
          ).font(.caption)
          Text("Pending retries: \(model.state.retries.count)")
          HelpButton(page: "troubleshooting-mail-integration")
        }
      }.formStyle(.grouped).tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
    }.frame(width: 730, height: 650).padding(12)
  }
}
struct PolicyView: View {
  @Bindable var model: AppModel
  @State private var policy = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Your mail preferences").font(.title2.bold())
      Text(
        "Describe what you want to receive. Your policy is sent to Anthropic with eligible messages."
      )
      TextEditor(text: $policy).font(.body).border(.quaternary).accessibilityLabel(
        "Mail filtering policy"
      )
      Text("\(policy.count)/4,000 characters").font(.caption).foregroundStyle(.secondary)
      HStack {
        Button("Reset to default") { policy = PromptBuilder.defaultPolicy }
        Spacer()
        Button("Save preferences") {
          model.setSetting(\.policy, to: policy)
        }.disabled(policy.count > 4000)
      }
      HelpButton(page: "how-decisions-are-made")
    }.padding(24).onAppear { policy = model.state.settings.policy }
  }
}
