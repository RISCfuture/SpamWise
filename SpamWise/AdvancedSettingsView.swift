import SwiftUI
import SpamWiseCore

struct AdvancedSettingsView: View {
  @Bindable var model: AppModel

  var body: some View {
    Form {
      Section {
        DisclosureGroup("Context limits") {
          Stepper(
            "Recent corrections: \(model.state.settings.correctionLimit, format: .number)",
            value: model.settingBinding(\.correctionLimit),
            in: 0...100,
            step: 5
          )
          Stepper(
            "Body budget: ~\(model.state.settings.bodyTokenBudget, format: .number) tokens",
            value: model.settingBinding(\.bodyTokenBudget),
            in: 100...4000,
            step: 100
          )
          Text(
            "Body length uses a four-characters-per-token estimate. Quoted reply chains and attachments are omitted."
          )
          .foregroundStyle(.secondary)
        }
      }
      LearningSettingsView(model: model)
      EvidenceSettingsView(model: model)
      Section { BackupSettingsView(model: model) }
      Section {
        DisclosureGroup("Integration details") {
          LabeledContent("Incoming route", value: model.state.settings.route.localizedTitle)
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
      }
    }.formStyle(.grouped)
  }
}

#Preview("Advanced") { AdvancedSettingsView(model: PreviewHelper.model()) }
