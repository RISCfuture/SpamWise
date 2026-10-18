import SwiftUI
import SpamWiseCore

struct AdvancedSettingsView: View {
  @Bindable var model: AppModel

  var body: some View {
    Form {
      Section {
        DisclosureGroup("Context limits") {
          Stepper(
            "Similar corrections: \(model.state.settings.correctionLimit, format: .number)",
            value: model.settingBinding(\.correctionLimit),
            in: 0...20
          )
          Stepper(
            "Body budget: ~\(model.state.settings.bodyTokenBudget, format: .number) tokens",
            value: model.settingBinding(\.bodyTokenBudget),
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
      LearningSettingsView(model: model)
      EvidenceSettingsView(model: model)
      Section { BackupSettingsView(model: model) }
      Section {
        DisclosureGroup("Integration details") {
          LabeledContent(
            "Incoming route",
            value: model.state.settings.incomingRoute.localizedTitle
          )
          LabeledContent("Pending retries", value: model.state.retries.count.formatted())
          HStack(alignment: .top) {
            Text(
              "MailKit remains dry-run-only pending signed timing and account identity validation."
            )
            .foregroundStyle(.secondary)
            Spacer()
            HelpButton(page: "troubleshooting-mail-integration")
          }
        }
        if model.state.settings.advancedOptions.transport == .appleMail {
          DisclosureGroup("Optional move test") { MoveTestView(model: model) }
        }
      }
    }.formStyle(.grouped)
  }
}

private struct MoveTestView: View {
  let model: AppModel

  var body: some View {
    Text(
      """
      Select one Inbox message whose subject begins “[SpamWise Probe]”. SpamWise moves it to Junk \
      and back, then adds an orange flag, checking each move after 30 seconds. Dry run and \
      validation stay unchanged.
      """
    )
    Button("Test selected message") { model.testDisposableMessage() }
      .disabled(model.busy)
    if !model.moveTestStatus.isEmpty {
      Text(model.moveTestStatus).textSelection(.enabled)
    }
  }
}

#Preview("Advanced") { AdvancedSettingsView(model: PreviewHelper.model()) }
#Preview("Move test") { Form { MoveTestView(model: PreviewHelper.model()) }.formStyle(.grouped) }
