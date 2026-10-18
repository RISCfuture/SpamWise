import SwiftUI
import SpamWiseCore

struct AdvancedSettingsView: View {
  let model: AppModel

  private var settings: SettingsModel { model.settings }

  var body: some View {
    Form {
      Section {
        DisclosureGroup("Context limits") {
          Stepper(
            "Similar corrections: \(settings.settings.correctionLimit, format: .number)",
            value: settings.binding(\.correctionLimit),
            in: 0...20
          )
          Stepper(
            "Body budget: ~\(settings.settings.bodyTokenBudget, format: .number) tokens",
            value: settings.binding(\.bodyTokenBudget),
            in: 100...4000,
            step: 100
          )
          Text(
            """
            Body length uses a four-characters-per-token estimate. Quoted text in replies is \
            shortened. Attachment text is included only when enabled.
            """
          )
          .foregroundStyle(.secondary)
        }
      }
      LearningSettingsView(
        settings: settings,
        shared: model.shared,
        rules: model.rules,
        activity: model.activity
      )
      EvidenceSettingsView(settings: settings, credentials: model.credentials)
      Section { BackupSettingsView(backup: model.backup) }
      Section {
        DisclosureGroup("Integration details") {
          LabeledContent(
            "Incoming route",
            value: settings.settings.incomingRoute.localizedTitle
          )
          LabeledContent("Pending retries", value: model.shared.state.retries.count.formatted())
        }
        if settings.settings.advancedOptions.transport == .appleMail {
          DisclosureGroup("Optional move test") { MoveTestView(mail: model.mail) }
        }
      }
    }.formStyle(.grouped)
  }
}

private struct MoveTestView: View {
  let mail: MailConnectionModel

  var body: some View {
    Text(
      """
      Select one Inbox message whose subject begins “[SpamWise Probe]”. SpamWise moves it to Junk \
      and back, then adds an orange flag, checking each move after 30 seconds. Dry run and \
      validation stay unchanged.
      """
    )
    HStack {
      Button("Test selected message") { mail.testDisposableMessage() }
        .disabled(mail.moveTest.isBusy)
      if mail.moveTest.isBusy {
        ProgressView().controlSize(.small)
        Text("Testing the selected message; waiting for Mail to show each move…")
          .foregroundStyle(.secondary)
      }
    }
    OperationStatusView(operation: mail.moveTest)
  }
}

#Preview("Advanced") { AdvancedSettingsView(model: PreviewHelper.model()) }
#Preview("Move test") {
  Form { MoveTestView(mail: PreviewHelper.model().mail) }.formStyle(.grouped)
}
