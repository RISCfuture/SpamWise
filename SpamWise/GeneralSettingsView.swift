import SwiftUI
import SpamWiseCore

struct GeneralSettingsView: View {
  @Bindable var model: AppModel
  @State private var showsSetup = false

  var body: some View {
    Form {
      StartupSettingsView()
      Section("Filtering") {
        Picker("Filtering strength", selection: model.settingBinding(\.strength)) {
          ForEach(FilteringStrength.allCases, id: \.self) { strength in
            Text(strength.localizedTitle).tag(strength)
          }
        }
        Text("Confidence thresholds are provisional until calibrated with reviewed mail.")
          .foregroundStyle(.secondary)
        Picker("Review treatment", selection: model.settingBinding(\.review)) {
          Text("Orange flag (keep in Inbox)").tag(ReviewTreatment.orangeFlag)
          Text("Orange background (keep in Inbox)").tag(ReviewTreatment.orangeBackground)
        }
        Toggle("Dry run — do not change mail", isOn: model.settingBinding(\.dryRun))
          .disabled(model.state.settings.validatedAccounts.isEmpty)
          .accessibilityIdentifier("settings.dryRun")
        Toggle(
          "Mark as read after a confirmed Junk move",
          isOn: Binding(
            get: { model.state.settings.mailOptions.markJunkRead == true },
            set: { enabled in model.editSettings { $0.mailOptions.markJunkRead = enabled } }
          )
        )
        if model.state.settings.validatedAccounts.isEmpty {
          Text("Validate a disposable message in Accounts before enabling mail actions.")
            .foregroundStyle(.secondary)
        }
      }
      Section("Review") {
        NotificationSettingsView(model: model)
        Toggle("Show a weekly Review digest", isOn: model.advancedBinding(\.weeklyDigest))
        Text(
          "A local summary of unresolved Review items from the last seven days. No email is sent."
        )
        .foregroundStyle(.secondary)
      }
      Section {
        HStack {
          Button("Show setup") { showsSetup = true }
          Spacer()
          HelpButton(page: "filtering-strength")
        }
      }
    }.formStyle(.grouped)
      .sheet(isPresented: $showsSetup) {
        OnboardingView(model: model) { showsSetup = false }
      }
  }
}

#Preview("General") { GeneralSettingsView(model: PreviewHelper.model()) }
