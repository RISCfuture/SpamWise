import SwiftUI
import SpamWiseCore
import MailIntegration

struct MailHealthView: View {
  let model: AppModel
  @State private var showsFolders = false

  private var mail: MailConnectionModel { model.mail }

  var body: some View {
    Button("Configure folders…") {
      showsFolders = true; model.folders.discoverFolders()
    }
    .sheet(isPresented: $showsFolders) {
      FolderSettingsView(folders: model.folders, shared: model.shared, accounts: mail.accounts)
    }
    if mail.accounts.isEmpty {
      Text("Check Mail connection to discover accounts.")
    }
    ForEach(mail.accounts) { account in
      AccountScopeToggle(
        account: account,
        accounts: mail.accounts,
        settings: model.settings,
        scanning: model.scanning
      )
      MailDestinationView(mail: mail, shared: model.shared, accountID: account.id)
      if let health = model.shared.scanHealth[account.id] {
        AccountHealthView(health: health)
      }
      HistoricalInboxView(olderMail: model.olderMail, shared: model.shared, accountID: account.id)
    }
    Text(
      "Checks read the newest Inbox mail first, then earlier pages. Counts do not guarantee delivery."
    )
    .foregroundStyle(.secondary)
  }
}

/// Whether automatic checks include an account; including one starts its filtering from now.
private struct AccountScopeToggle: View {
  let account: MailAccount
  let accounts: [MailAccount]
  let settings: SettingsModel
  let scanning: ScanCoordinator

  var body: some View {
    Toggle(
      account.name,
      isOn: Binding(
        get: { settings.settings.mailOptions.accountIDs?.contains(account.id) ?? true },
        set: { included in
          let all = Set(accounts.map(\.id)), id = account.id
          settings.editSettings {
            var selected = $0.mailOptions.accountIDs ?? all
            if included { selected.insert(id) } else { selected.remove(id) }
            $0.mailOptions.accountIDs = selected.isSuperset(of: all) ? nil : selected
          }
          if included { scanning.startInboxFiltering(for: [account], replacing: true) }
        }
      )
    )
  }
}

private struct AccountHealthView: View {
  let health: MailScanHealth

  var body: some View {
    if let date = health.lastSuccess {
      LabeledContent("Last successful page", value: date.formatted())
      LabeledContent("Messages since start", value: health.observedTotal.formatted())
      LabeledContent("Backfill position", value: health.nextOffset.formatted())
      UnreadableMailView(count: health.unavailableCount)
    } else {
      Text("No successful scan yet")
    }
    if let failure = health.failure {
      StatusLabel(status: .failure(OperationFailure(message: failure)))
    }
  }
}

#Preview("No accounts") { Form { MailHealthView(model: PreviewHelper.model()) } }
#Preview("Failing account") {
  var health = MailScanHealth(accountName: "Account")
  health.failure = "Mail didn’t respond in time."
  return Form { AccountHealthView(health: health) }
}
