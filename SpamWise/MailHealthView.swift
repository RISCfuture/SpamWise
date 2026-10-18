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
              $0.mailOptions.accountIDs = selected.isSuperset(of: all) ? nil : selected
            }
            if included { model.startInboxFiltering(for: [account], replacing: true) }
          }
        )
      )
      MailDestinationView(model: model, accountID: account.id)
      if let health = model.scanHealth[account.id] {
        if let date = health.lastSuccess {
          LabeledContent("Last successful page", value: date.formatted())
          LabeledContent("Messages since start", value: health.observedTotal.formatted())
          LabeledContent("Backfill position", value: health.nextOffset.formatted())
          UnreadableMailView(count: health.unavailableCount)
        } else {
          Text("No successful scan yet")
        }
        if let failure = health.failure { Text(failure).textSelection(.enabled) }
      }
      HistoricalInboxView(model: model, accountID: account.id)
    }
    Text(
      "Checks read the newest Inbox mail first, then earlier pages. Counts do not guarantee delivery."
    )
    .foregroundStyle(.secondary)
  }
}

#Preview("No accounts") { Form { MailHealthView(model: PreviewHelper.model()) } }
