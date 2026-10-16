import SwiftUI
import SpamWiseCore
import MailIntegration

struct MailHealthView: View {
  let model: AppModel
  @State private var showsFolders = false

  var body: some View {
    Button("Configure folders…") {
      showsFolders = true; model.discoverFolders()
    }
    .disabled(model.busy)
    .sheet(isPresented: $showsFolders) { FolderSettingsView(model: model) }
    if model.accounts.isEmpty {
      Text("Check Mail connection to discover accounts.")
    }
    ForEach(model.accounts) { account in
      Toggle(
        account.name,
        isOn: Binding(
          get: { model.state.settings.mailOptions.accountIDs?.contains(account.id) ?? true },
          set: { included in
            let all = Set(model.accounts.map(\.id))
            model.editSettings {
              var selected = $0.mailOptions.accountIDs ?? all
              if included { selected.insert(account.id) } else { selected.remove(account.id) }
              $0.mailOptions.accountIDs = selected
            }
          }
        )
      )
      MailDestinationView(model: model, accountID: account.id)
      if let health = model.scanHealth[account.id] {
        if let date = health.lastSuccess {
          LabeledContent("Last successful page", value: date.formatted())
          LabeledContent("Observed Inbox messages", value: health.observedTotal.formatted())
          LabeledContent("Next page offset", value: health.nextOffset.formatted())
          UnreadableMailView(count: health.unavailableCount)
        } else {
          Text("No successful scan yet")
        }
        if let failure = health.failure { Text(failure).textSelection(.enabled) }
      }
    }
    Text(
      "Mailbox changes can shift pages. Repeating sweeps revisit them; counts do not guarantee delivery."
    )
    .foregroundStyle(.secondary)
  }
}

#Preview("No accounts") { Form { MailHealthView(model: PreviewHelper.model()) } }
