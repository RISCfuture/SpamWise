import SwiftUI
import SpamWiseCore

/// Every key and password SpamWise keeps in Keychain, each removable, and a way to remove them all.
struct CredentialsSettingsView: View {
  let credentials: CredentialsModel
  @State private var confirmingRemoveAll = false

  private var stored: [StoredCredential] {
    credentials.saved.keys.sorted { $0.displayOrder < $1.displayOrder }
  }

  var body: some View {
    Section("Keys and passwords") {
      ForEach(stored) { credential in
        SavedCredentialRow(credentials: credentials, credential: credential)
      }
      Button("Remove All SpamWise Keys and Passwords…", role: .destructive) {
        confirmingRemoveAll = true
      }
      .disabled(credentials.storedCredentials.isBusy)
      .accessibilityIdentifier("credentials.removeAll")
      OperationStatusView(
        operation: credentials.storedCredentials,
        identifier: "credentials.status"
      )
    }
    .task { credentials.refreshSaved() }
    .confirmationDialog(
      "Remove all SpamWise keys and passwords?",
      isPresented: $confirmingRemoveAll,
      titleVisibility: .visible
    ) {
      Button("Remove All", role: .destructive) { credentials.removeAll() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        """
        SpamWise removes every provider key, the Spamhaus key and the IMAP password from Keychain. \
        Mail isn’t classified until you add a key again.
        """
      )
    }
  }
}

/// One credential's saved state, with Remove when it is saved.
struct SavedCredentialRow: View {
  let credentials: CredentialsModel
  let credential: StoredCredential

  var body: some View {
    LabeledContent(credential.localizedTitle) {
      switch credentials.saved[credential] {
        case .saved:
          HStack {
            Text("Saved").foregroundStyle(.secondary)
            Button("Remove") { credentials.remove(credential) }
              .disabled(credentials.storedCredentials.isBusy)
              .accessibilityLabel(Text("Remove \(credential.localizedTitle)"))
          }
        case .notSaved: Text("Not saved").foregroundStyle(.secondary)
        case .unknown, nil: Text("Unknown").foregroundStyle(.secondary)
      }
    }
  }
}

#Preview("Keys and passwords") {
  Form { CredentialsSettingsView(credentials: PreviewHelper.model().credentials) }
    .formStyle(.grouped)
}
