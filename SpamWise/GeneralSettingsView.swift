import SwiftUI
import SpamWiseCore

struct GeneralSettingsView: View {
  @Bindable var model: AppModel
  @State private var showsSetup = false

  var body: some View {
    Form {
      StartupSettingsView()
      UpdateSettingsView()
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
        DryRunToggle(model: model)
        Text(
          "Previewed mail keeps its recorded decision after dry run ends. Correct it from Activity to act on it."
        )
        .foregroundStyle(.secondary)
        Toggle(
          "Mark as read after a confirmed Junk move",
          isOn: Binding(
            get: { model.state.settings.mailOptions.markJunkRead == true },
            set: { enabled in model.editSettings { $0.mailOptions.markJunkRead = enabled } }
          )
        )
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

private struct DryRunToggle: View {
  let model: AppModel
  @State private var confirmsLiveFiltering = false

  private var dryRun: Binding<Bool> {
    Binding(
      get: { model.state.settings.dryRun },
      set: { enabled in
        if enabled { model.setSetting(\.dryRun, to: true) } else { confirmsLiveFiltering = true }
      }
    )
  }

  var body: some View {
    Toggle("Dry run — do not change mail", isOn: dryRun)
      .disabled(model.state.settings.validatedAccounts.isEmpty)
      .accessibilityIdentifier("settings.dryRun")
      .confirmationDialog(
        "Turn off dry run?",
        isPresented: $confirmsLiveFiltering,
        titleVisibility: .visible
      ) {
        Button("Turn off dry run") { model.setSetting(\.dryRun, to: false) }
          .accessibilityIdentifier("settings.dryRun.confirm")
        Button("Cancel", role: .cancel) {}
          .accessibilityIdentifier("settings.dryRun.cancel")
      } message: {
        Text(
          """
          SpamWise will move new Junk to each validated account’s Junk mailbox and mark Review \
          messages in Inbox. It checks every move afterward. If Mail doesn’t confirm a move, \
          SpamWise doesn’t retry or reverse it, and Activity shows the failure so you can check \
          the message in Mail.
          """
        )
      }
    if model.state.settings.validatedAccounts.isEmpty {
      Text("Validate the Inbox and Junk mailboxes before turning off dry run.")
        .foregroundStyle(.secondary)
      if model.state.settings.advancedOptions.transport == .imap {
        IMAPRoleCheck(model: model)
      } else {
        MailRoleCheck(model: model)
      }
    }
  }
}

private struct MailRoleCheck: View {
  let model: AppModel

  var body: some View {
    Button("Check Mail connection") { model.checkMail() }
      .accessibilityIdentifier("settings.checkMail")
      .disabled(model.busy)
    Text(model.mailStatus)
      .foregroundStyle(.secondary)
      .accessibilityIdentifier(
        model.mailPermissionDenied ? "settings.mailPermissionDenied" : "settings.mailStatus"
      )
  }
}

private struct IMAPRoleCheck: View {
  @State private var connection: IMAPConnectionModel

  var body: some View {
    Button("Check read-only connection") { connection.check() }
      .disabled(connection.busy)
      .task { await connection.load() }
    Text(connection.status).foregroundStyle(.secondary)
  }

  init(model: AppModel) {
    _connection = State(initialValue: IMAPConnectionModel(model: model))
  }
}

#Preview("General") { GeneralSettingsView(model: PreviewHelper.model()) }
#Preview("Dry run toggle") {
  Form { DryRunToggle(model: PreviewHelper.model()) }.formStyle(.grouped)
}
#Preview("Dry run toggle, IMAP") {
  Form { DryRunToggle(model: PreviewHelper.model(transport: .imap)) }.formStyle(.grouped)
}
