import SwiftUI
import SpamWiseCore

/**
 The mail server an account trusts to check senders' authentication, or the server SpamWise
 detected in its mail, with controls to confirm, edit or stop trusting it.
 */
struct AccountTrustView: View {
  let trust: AuthenticationTrustModel
  let accountID: String
  @State private var editing = false

  private var authentication: AccountAuthentication? { trust.accounts[accountID] }
  private var trusted: [String] { (authentication?.trustedServers ?? []).sorted() }

  var body: some View {
    LabeledContent("Trusted mail server") {
      if trusted.isEmpty {
        Text("None").foregroundStyle(.secondary)
      } else {
        Text(trusted.joined(separator: ", ")).textSelection(.enabled)
      }
    }
    .sheet(isPresented: $editing) {
      TrustedServersEditor(trust: trust, accountID: accountID, initial: trusted)
    }
    if trusted.isEmpty {
      TrustDetectionView(
        detection: authentication?.detection,
        confirm: { trust.confirmDetected(accountID: accountID) },
        edit: { editing = true }
      )
    } else {
      HStack {
        Button("Edit…") { editing = true }
        Button("Stop Trusting") { trust.stopTrusting(accountID: accountID) }
      }
    }
    OperationStatusView(operation: trust.operation(for: accountID))
  }
}

/// What SpamWise has learned about an untrusted account's mail server, and how to trust one.
private struct TrustDetectionView: View {
  let detection: AuthServerDetection?
  let confirm: () -> Void
  let edit: () -> Void

  var body: some View {
    switch detection {
      case .detected(let servers):
        LabeledContent("Detected server") {
          Text(servers.sorted().joined(separator: ", ")).textSelection(.enabled)
        }
        HStack {
          Button("Trust Detected Server", action: confirm)
            .accessibilityIdentifier("account.trust.confirm")
          Button("Enter Another…", action: edit)
        }
      case .inconsistent:
        Text("SpamWise couldn’t tell which server receives this account’s mail. Enter it yourself.")
          .foregroundStyle(.secondary)
        Button("Enter Server…", action: edit)
      case let .collecting(observed, required):
        Text("Finding this account’s mail server: \(observed) of \(required) messages read.")
          .foregroundStyle(.secondary)
        Button("Enter Server…", action: edit)
      case nil:
        Text("SpamWise finds this account’s mail server as new mail arrives.")
          .foregroundStyle(.secondary)
        Button("Enter Server…", action: edit)
    }
    Text(
      """
      Until you trust a server, Contacts, people you’ve written to and Allow rules only make Junk \
      less likely, because a sender’s address can be forged.
      """
    )
    .foregroundStyle(.secondary)
  }
}

/// Edits the list of servers an account trusts, saving only when the list is valid.
private struct TrustedServersEditor: View {
  let trust: AuthenticationTrustModel
  let accountID: String
  @State private var text: String
  @Environment(\.dismiss)
  private var dismiss

  private var operation: TrackedOperation { trust.operation(for: accountID) }

  var body: some View {
    NavigationStack {
      Form {
        TextField("Servers", text: $text, prompt: Text("mx.example.com"))
          .accessibilityIdentifier("account.trust.servers")
        Text(
          """
          Enter the server named first in this account’s Authentication-Results headers. Separate \
          several with commas.
          """
        )
        .foregroundStyle(.secondary)
        OperationStatusView(operation: operation)
      }
      .formStyle(.grouped)
      .navigationTitle("Trusted Mail Server")
      .toolbar {
        ConfirmationToolbarItems(
          confirmTitle: "Save",
          confirmIdentifier: "account.trust.save",
          canConfirm: !operation.isBusy,
          cancel: { dismiss() },
          confirm: save
        )
      }
    }
    .frame(minWidth: 420, minHeight: 220)
  }

  init(trust: AuthenticationTrustModel, accountID: String, initial: [String]) {
    self.trust = trust
    self.accountID = accountID
    _text = State(initialValue: initial.joined(separator: ", "))
  }

  private func save() {
    Task {
      await trust.save(text, accountID: accountID).value
      if operation.failure == nil { dismiss() }
    }
  }
}

#Preview("Collecting") {
  let model = PreviewHelper.model()
  Form { AccountTrustView(trust: model.trust, accountID: "preview") }.formStyle(.grouped)
}
#Preview("Detected") {
  let model = PreviewHelper.accountsModel()
  Form { AccountTrustView(trust: model.trust, accountID: "icloud") }.formStyle(.grouped)
}
#Preview("Trusted") {
  let model = PreviewHelper.accountsModel()
  Form { AccountTrustView(trust: model.trust, accountID: "gmail") }.formStyle(.grouped)
}
