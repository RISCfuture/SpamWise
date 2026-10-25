import SwiftUI
import UniformTypeIdentifiers
import SpamWiseCore

/**
 Enters a backup's recovery key, chooses the backup and confirms the restore.

 - Parameters:
   - isBusy: Whether a restore or export is running.
   - restore: Restores the chosen backup file with the entered key.
 */
struct BackupRestoreControls: View {
  let isBusy: Bool
  let restore: (URL, String) -> Void
  @State private var recoveryKey = ""
  @State private var importing = false
  @State private var pendingURL: URL?
  @State private var importStatus: OperationStatus?

  private var confirming: Binding<Bool> {
    Binding(get: { pendingURL != nil }, set: { if !$0 { pendingURL = nil } })
  }

  var body: some View {
    SecureField("Recovery key", text: $recoveryKey, prompt: Text("The backup’s recovery key"))
      .accessibilityIdentifier("backup.key")
    Button("Restore Backup…") { importing = true }
      .disabled(recoveryKey.isEmpty || isBusy)
      .accessibilityIdentifier("backup.restore")
      .fileImporter(isPresented: $importing, allowedContentTypes: [.spamWiseBackup]) { result in
        switch result {
          case .success(let url):
            importStatus = nil
            pendingURL = url
          case .failure:
            importStatus = .failure(
              OperationFailure(message: String(localized: "The backup couldn’t be opened."))
            )
        }
      }
      .confirmationDialog(
        "Restore from this backup?",
        isPresented: confirming,
        titleVisibility: .visible
      ) {
        Button("Restore and Pause Filtering", role: .destructive) {
          if let pendingURL { restore(pendingURL, recoveryKey) }
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text(
          """
          Your rules, additional instructions, corrections and learning are replaced with the \
          backup’s. Filtering pauses with dry run on until you check your accounts. Keys, \
          passwords and spending stay as they are.
          """
        )
      }
    StatusLabel(status: importStatus)
  }
}

#Preview("Restore") {
  Form { BackupRestoreControls(isBusy: false) { _, _ in } }.formStyle(.grouped)
}
