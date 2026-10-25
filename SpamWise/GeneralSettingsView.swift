import SwiftUI
import SpamWiseCore

struct GeneralSettingsView: View {
  let model: AppModel
  let showSetup: () -> Void

  private var settings: SettingsModel { model.settings }

  var body: some View {
    Form {
      StartupSettingsView(loginItem: settings.loginItem)
      MenuBarSettingsView(preferences: model.services.preferences)
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
      NotificationSettingsView(notifications: model.notifications, settings: settings)
      Section {
        HStack {
          Button("Show Setup", action: showSetup)
          Spacer()
          HelpButton(page: "filtering-strength")
        }
      }
    }.formStyle(.grouped)
  }
}

/// Whether SpamWise shows its menu bar item, an interface preference of this Mac.
private struct MenuBarSettingsView: View {
  @AppStorage private var showsMenuBarItem: Bool

  var body: some View {
    Section {
      Toggle("Show SpamWise in the menu bar", isOn: $showsMenuBarItem)
        .accessibilityIdentifier("settings.menuBar")
    } footer: {
      Text("When it’s hidden, click SpamWise in the Dock to open Activity.")
        .foregroundStyle(.secondary)
    }
  }

  init(preferences: UserDefaults) {
    _showsMenuBarItem = MenuBarLabel.isShown(in: preferences)
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
      .liveFilteringConfirmation(isPresented: $confirmsLiveFiltering, settings: settings)
    if settings.settings.validatedAccounts.isEmpty {
      if settings.settings.advancedOptions.transport == .imap {
        Text(
          """
          Check the connection so SpamWise can find the account’s Inbox and Junk before you turn \
          off dry run.
          """
        )
        .foregroundStyle(.secondary)
        IMAPRoleCheck(imap: imap)
      } else {
        Text(
          """
          Check the Mail connection so SpamWise can find each account’s Inbox and Junk before you \
          turn off dry run.
          """
        )
        .foregroundStyle(.secondary)
        MailRoleCheck(mail: mail)
      }
    }
  }
}

private struct MailRoleCheck: View {
  let mail: MailConnectionModel

  var body: some View {
    HStack {
      Button("Check Mail Connection") { mail.checkConnection() }
        .accessibilityIdentifier("settings.checkMail")
      if mail.check.isBusy {
        ProgressView { Text("Checking the Mail connection…") }.labelsHidden().controlSize(.small)
      }
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
      Button("Check Connection") { imap.check() }
      if imap.operation.isBusy {
        ProgressView { Text("Checking the connection…") }.labelsHidden().controlSize(.small)
      }
    }
    .task { imap.loadIfNeeded() }
    OperationStatusView(operation: imap.operation)
  }
}

#Preview("General") { GeneralSettingsView(model: PreviewHelper.model()) {} }
#Preview("Menu bar") {
  Form { MenuBarSettingsView(preferences: PreviewHelper.model().services.preferences) }
    .formStyle(.grouped)
}
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
