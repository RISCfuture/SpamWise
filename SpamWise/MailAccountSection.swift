import SwiftUI
import SpamWiseCore
import MailIntegration

/// One Settings section per Apple Mail account, then the folders SpamWise filters or learns from.
struct MailAccountsView: View {
  let model: AppModel
  @State private var showsFolders = false

  private var accounts: [MailAccount] { model.mail.accounts }

  var body: some View {
    if accounts.isEmpty {
      Section("Accounts") {
        Text("Check Mail Connection to show your accounts.").foregroundStyle(.secondary)
      }
    }
    ForEach(accounts) { account in
      MailAccountSection(model: model, accountID: account.id, name: account.name) {
        AccountFilterToggle(
          account: account,
          accounts: accounts,
          settings: model.settings,
          scanning: model.scanning
        )
      }
    }
    Section("Folders") {
      LabeledContent(
        "Folder plans",
        value: model.shared.settings.mailOptions.folderPlans.count.formatted()
      )
      Button("Configure Folders…") {
        showsFolders = true
        model.folders.discoverFolders()
      }
      .accessibilityIdentifier("accounts.folders")
    }
    .sheet(isPresented: $showsFolders) {
      FolderSettingsView(folders: model.folders, shared: model.shared, accounts: accounts)
    }
  }
}

/**
 An account's filtering, health and trust, headed by its name.

 Paging diagnostics, mailbox roles and older mail sit in disclosures below the summary.
 */
struct MailAccountSection<Scope: View>: View {
  let model: AppModel
  let accountID: String
  let name: String
  @ViewBuilder let scope: () -> Scope

  private var health: MailScanHealth? { model.shared.scanHealth[accountID] }
  private var summary: AccountHealthSummary { AccountHealthSummary(health: health) }
  private var isAppleMail: Bool { model.shared.settings.advancedOptions.transport == .appleMail }
  private var needsMailboxCheck: Bool {
    !model.shared.settings.validatedAccounts.contains(accountID)
  }

  var body: some View {
    Section {
      scope()
      AccountHealthRow(summary: summary)
      if needsMailboxCheck { MailboxCheckWarning(isAppleMail: isAppleMail) }
      AccountCoverageView(summary: summary)
      AccountTrustView(trust: model.trust, accountID: accountID)
      DisclosureGroup("Mailboxes and Details") {
        if isAppleMail {
          MailDestinationView(mail: model.mail, shared: model.shared, accountID: accountID)
        }
        AccountScanDiagnostics(health: health)
      }
      if isAppleMail, model.olderMail.inboxStart(accountID: accountID) != nil {
        DisclosureGroup("Older mail") {
          HistoricalInboxView(
            olderMail: model.olderMail,
            shared: model.shared,
            accountID: accountID
          )
        }
      }
    } header: {
      Text(name)
    }
  }
}

extension MailAccountSection where Scope == EmptyView {
  /// A section without an account-inclusion toggle, for connections that check every account.
  init(model: AppModel, accountID: String, name: String) {
    self.init(model: model, accountID: accountID, name: name) { EmptyView() }
  }
}

/// Why SpamWise won't move an account's mail yet, and where to fix it.
private struct MailboxCheckWarning: View {
  let isAppleMail: Bool

  var body: some View {
    if isAppleMail {
      WarningLabel(
        """
        SpamWise won’t move this account’s mail until it finds the Inbox and Junk mailboxes. Check \
        Mail Connection, or open Mailboxes and Details and choose Check Mailboxes.
        """
      )
    } else {
      WarningLabel(
        """
        SpamWise won’t move this account’s mail until it finds the Inbox and Junk mailboxes. Check \
        the IMAP connection.
        """
      )
    }
  }
}

/// Whether automatic checks include an account; including one starts its filtering from now.
private struct AccountFilterToggle: View {
  let account: MailAccount
  let accounts: [MailAccount]
  let settings: SettingsModel
  let scanning: ScanCoordinator

  var body: some View {
    Toggle(
      "Filter this account",
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
    .accessibilityLabel(Text("Filter \(account.name)"))
    .accessibilityIdentifier("account.filter")
  }
}

/// When the account was last checked, or the problem that keeps it from being checked.
private struct AccountHealthRow: View {
  let summary: AccountHealthSummary

  var body: some View {
    switch summary.state {
      case .notChecked:
        LabeledContent("Status", value: String(localized: "Not checked yet"))
      case .checked(let date):
        TimelineView(.everyMinute) { _ in
          LabeledContent("Status", value: String(localized: "Last checked \(relative(date))"))
        }
      case .late(let date):
        WarningLabel(
          "Last checked \(relative(date)). Checks haven’t run since; keep SpamWise and Mail open."
        )
      case .failing(let failure):
        WarningLabel(verbatim: failure)
      case .stalled:
        WarningLabel(
          """
          Mail keeps timing out on some messages, so checks read fewer at a time and skip a \
          message that never loads.
          """
        )
    }
  }

  private func relative(_ date: Date) -> String {
    date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
  }
}

/// How the latest check handled the messages it read, and how much older mail is left.
private struct AccountCoverageView: View {
  let summary: AccountHealthSummary

  var body: some View {
    if let coverage = summary.coverage, coverage.visited > 0 {
      LabeledContent("Latest check") {
        Text(
          """
          \(coverage.classified) Good or Junk · \(coverage.reviewed) Review · \
          \(coverage.unclassified) not classified
          """
        )
      }
    }
    if summary.backlog > 0 {
      LabeledContent("Older mail still to check", value: summary.backlog.formatted())
    }
    UnreadableMailView(messageCount: summary.unreadable)
  }
}

/// Paging details of the account's checks, for troubleshooting.
private struct AccountScanDiagnostics: View {
  let health: MailScanHealth?

  var body: some View {
    if let health {
      LabeledContent("Filtering started", value: optional(health.inboxStart))
      LabeledContent("Messages since then", value: health.observedTotal.formatted())
      LabeledContent("Last attempt", value: optional(health.lastAttempt))
      LabeledContent("Last successful read", value: optional(health.lastSuccess))
      LabeledContent("Last full pass", value: optional(health.lastCompletedSweep))
      LabeledContent("Failed checks in a row", value: health.consecutiveFailures.formatted())
      LabeledContent("Timeouts in a row", value: health.consecutiveTimeouts.formatted())
    } else {
      Text("No checks recorded yet.").foregroundStyle(.secondary)
    }
  }

  private func optional(_ date: Date?) -> String {
    date?.formatted(date: .abbreviated, time: .shortened) ?? String(localized: "Never")
  }
}

#Preview("Accounts") {
  let model = PreviewHelper.accountsModel()
  Form { MailAccountsView(model: model) }.formStyle(.grouped)
}
#Preview("No accounts") {
  Form { MailAccountsView(model: PreviewHelper.model()) }.formStyle(.grouped)
}
#Preview("Failing account") {
  let model = PreviewHelper.accountsModel(failing: true)
  Form { MailAccountsView(model: model) }.formStyle(.grouped)
}
