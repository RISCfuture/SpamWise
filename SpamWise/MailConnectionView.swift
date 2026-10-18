import SwiftUI
import SpamWiseCore

/// Connects SpamWise to Apple Mail: Automation permission and the accounts Mail reports.
struct MailConnectionView: View {
  let mail: MailConnectionModel

  private var showsAutomationDenied: Bool {
    mail.automation == .notAuthorized && mail.check.failure?.recovery != .openAutomationSettings
  }

  var body: some View {
    Section("Apple Mail") {
      Text("SpamWise reads and moves mail through Mail. Allow access when macOS asks.")
        .foregroundStyle(.secondary)
      HStack {
        Button("Check Mail Connection") { mail.checkConnection() }
          .accessibilityIdentifier("mail.check")
        if mail.check.isBusy { ProgressView().controlSize(.small) }
      }
      MailConnectionStatus(
        mail: mail,
        identifier: mail.permissionDenied ? "mail.permissionDenied" : "mail.status"
      )
      if showsAutomationDenied {
        AutomationDeniedView()
      } else if mail.automation == .mailNotRunning {
        Text("Open Mail so SpamWise can check your accounts.").foregroundStyle(.secondary)
      }
    }
  }

  init(mail: MailConnectionModel) { self.mail = mail }

  /// The connection section over the app's Mail model, as setup presents it.
  init(model: AppModel) { self.init(mail: model.mail) }
}

/// The latest connection check's result, or what to do before the first check.
struct MailConnectionStatus: View {
  let mail: MailConnectionModel
  let identifier: String

  var body: some View {
    if mail.check.isBusy {
      Text("Waiting for you to allow access to Mail…").foregroundStyle(.secondary)
        .accessibilityIdentifier(identifier)
    } else if mail.check.status == nil {
      Text("Not checked yet").foregroundStyle(.secondary)
        .accessibilityIdentifier(identifier)
    } else {
      OperationStatusView(operation: mail.check, identifier: identifier)
    }
  }
}

#Preview("Mail connection") {
  Form { MailConnectionView(mail: PreviewHelper.model().mail) }.formStyle(.grouped)
}
#Preview("Permission denied") {
  let model = PreviewHelper.model()
  model.mail.checkConnection()
  return Form { MailConnectionView(mail: model.mail) }.formStyle(.grouped)
}
#Preview("Automation off") {
  let model = PreviewHelper.model()
  model.mail.automation = .notAuthorized
  return Form { MailConnectionView(mail: model.mail) }.formStyle(.grouped)
}
