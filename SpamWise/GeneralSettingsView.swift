import SwiftUI
import SpamWiseCore

struct GeneralSettingsView: View {
  let model: AppModel
  let showSetup: () -> Void

  private var settings: SettingsModel { model.settings }

  var body: some View {
    Form {
      StartupSettingsView()
      UpdateSettingsView()
      Section {
        Picker("Filtering strength", selection: settings.binding(\.strength)) {
          ForEach(FilteringStrength.allCases, id: \.self) { strength in
            Text(strength.localizedTitle).tag(strength)
          }
        }
        Picker("Review treatment", selection: settings.binding(\.review)) {
          Text("Orange flag (keep in Inbox)").tag(ReviewTreatment.orangeFlag)
          Text("Orange background (keep in Inbox)").tag(ReviewTreatment.orangeBackground)
        }
        DryRunToggle(settings: settings, mail: model.mail, imap: model.imap)
        Toggle(
          "Mark as read after a confirmed Junk move",
          isOn: settings.mailBinding(\.markJunkRead)
        )
      } header: {
        Text("Filtering")
      } footer: {
        Text(
          """
          In a dry run, Activity shows what SpamWise would do and mail stays where it is. When you \
          turn it off, SpamWise acts on the mail it checked that’s still in your Inbox.
          """
        )
        .foregroundStyle(.secondary)
      }
      Section {
        Toggle("Show a weekly Review digest", isOn: settings.advancedBinding(\.weeklyDigest))
      } header: {
        Text("Review")
      } footer: {
        Text(
          "Each week, lists Review messages from the last \(ReviewDigest.lookbackDays) days that you haven’t resolved. Nothing is emailed."
        )
        .foregroundStyle(.secondary)
      }
      Section {
        HStack {
          Button("Show setup", action: showSetup)
          Spacer()
          HelpButton(page: "filtering-strength")
        }
      }
    }.formStyle(.grouped)
  }
}

private struct DryRunToggle: View {
  let settings: SettingsModel
  let mail: MailConnectionModel
  let imap: IMAPConnectionModel
  @State private var confirmsLiveFiltering = false

  private var dryRun: Binding<Bool> {
    Binding(
      get: { settings.settings.dryRun },
      set: { enabled in
        if enabled { settings.setSetting(\.dryRun, to: true) } else { confirmsLiveFiltering = true }
      }
    )
  }

  var body: some View {
    Toggle("Dry run — do not change mail", isOn: dryRun)
      .disabled(settings.settings.validatedAccounts.isEmpty)
      .accessibilityIdentifier("settings.dryRun")
      .confirmationDialog(
        "Turn off dry run?",
        isPresented: $confirmsLiveFiltering,
        titleVisibility: .visible
      ) {
        Button("Turn off dry run") { settings.setSetting(\.dryRun, to: false) }
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
    if settings.settings.validatedAccounts.isEmpty {
      Text("Validate the Inbox and Junk mailboxes before turning off dry run.")
        .foregroundStyle(.secondary)
      if settings.settings.advancedOptions.transport == .imap {
        IMAPRoleCheck(imap: imap)
      } else {
        MailRoleCheck(mail: mail)
      }
    }
  }
}

private struct MailRoleCheck: View {
  let mail: MailConnectionModel

  var body: some View {
    HStack {
      Button("Check Mail connection") { mail.checkConnection() }
        .accessibilityIdentifier("settings.checkMail")
      if mail.check.isBusy { ProgressView().controlSize(.small) }
    }
    MailConnectionStatus(
      mail: mail,
      identifier: mail.permissionDenied ? "settings.mailPermissionDenied" : "settings.mailStatus"
    )
  }
}

private struct IMAPRoleCheck: View {
  let imap: IMAPConnectionModel

  var body: some View {
    HStack {
      Button("Check read-only connection") { imap.check() }
      if imap.operation.isBusy { ProgressView().controlSize(.small) }
    }
    .task { imap.loadIfNeeded() }
    OperationStatusView(operation: imap.operation)
  }
}

#Preview("General") { GeneralSettingsView(model: PreviewHelper.model()) {} }
#Preview("Dry run toggle") {
  let model = PreviewHelper.model()
  Form { DryRunToggle(settings: model.settings, mail: model.mail, imap: model.imap) }
    .formStyle(.grouped)
}
#Preview("Dry run toggle, IMAP") {
  let model = PreviewHelper.model(transport: .imap)
  Form { DryRunToggle(settings: model.settings, mail: model.mail, imap: model.imap) }
    .formStyle(.grouped)
}
