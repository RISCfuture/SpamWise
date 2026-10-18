import SwiftUI
import UniformTypeIdentifiers
import SpamWiseCore

/// Backup and restore in Advanced settings.
struct BackupSettingsView: View {
  let backup: BackupModel

  var body: some View {
    DisclosureGroup("Backup and restore") {
      BackupExportView(backup: backup)
      BackupRestoreControls(isBusy: backup.operation.isBusy) {
        backup.restore(from: $0, recoveryKey: $1)
      }
      OperationStatusView(operation: backup.operation, identifier: "backup.status")
    }
  }
}

/**
 Creates a recovery key, shows it so it can be kept, and exports a backup encrypted with it.

 Export waits for confirmation that the key is saved, and creating a new key over a shown one
 waits for confirmation too, because a backup can't be restored without its key.
 */
struct BackupExportView: View {
  let backup: BackupModel
  @State private var recoveryKey: String?
  @State private var includeContent = false
  @State private var confirmingNewKey = false
  @State private var confirmingExport = false
  @State private var exporting = false
  @State private var document: BackupDocument?
  @State private var fileStatus: OperationStatus?

  var body: some View {
    Text(
      """
      A backup holds your rules, policy, corrections and learning, encrypted with a recovery key. \
      Keys, passwords and spending stay on this Mac.
      """
    )
    .foregroundStyle(.secondary)
    if let recoveryKey {
      RecoveryKeyView(key: recoveryKey)
      Button("Create New Recovery Key…") { confirmingNewKey = true }
        .confirmationDialog(
          "Replace the recovery key?",
          isPresented: $confirmingNewKey,
          titleVisibility: .visible
        ) {
          Button("Create New Key") { self.recoveryKey = StateBackup.recoveryKey() }
          Button("Cancel", role: .cancel) {}
        } message: {
          Text("Backups you already exported with the current key still need that key to restore.")
        }
    } else {
      Button("Create Recovery Key") { recoveryKey = StateBackup.recoveryKey() }
        .accessibilityIdentifier("backup.createKey")
    }
    Toggle("Include saved message text", isOn: $includeContent)
    Button("Export Backup…") { confirmingExport = true }
      .disabled(recoveryKey == nil || backup.operation.isBusy)
      .accessibilityIdentifier("backup.export")
      .confirmationDialog(
        "Have you saved the recovery key?",
        isPresented: $confirmingExport,
        titleVisibility: .visible
      ) {
        Button("Export Backup") { prepareExport() }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("SpamWise can’t recover this key. Without it, this backup can’t be restored.")
      }
      .fileExporter(
        isPresented: $exporting,
        document: document,
        contentType: .spamWiseBackup,
        defaultFilename: "SpamWise.spamwisebackup"
      ) { fileStatus = ExportResult.status(of: $0, failure: "The backup couldn’t be saved.") }
    StatusLabel(status: fileStatus)
  }

  private func prepareExport() {
    guard let recoveryKey else { return }
    fileStatus = nil
    backup.export(recoveryKey: recoveryKey, includeContent: includeContent) { data in
      document = BackupDocument(data: data)
      exporting = true
    }
  }
}

/// A generated recovery key in selectable monospaced text, with Copy and Save to File.
private struct RecoveryKeyView: View {
  let key: String
  @State private var saving = false
  @State private var status: OperationStatus?

  var body: some View {
    LabeledContent("Recovery key") {
      Text(verbatim: key).font(.body.monospaced()).textSelection(.enabled)
        .accessibilityIdentifier("backup.recoveryKey")
    }
    HStack {
      Button("Copy") { copy() }
      Button("Save to File…") { saving = true }
        .fileExporter(
          isPresented: $saving,
          document: BackupDocument(data: Data(key.utf8)),
          contentType: .plainText,
          defaultFilename: String(localized: "SpamWise Recovery Key.txt")
        ) { status = ExportResult.status(of: $0, failure: "The recovery key couldn’t be saved.") }
    }
    StatusLabel(status: status)
  }

  private func copy() {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(key, forType: .string)
    status = .message(String(localized: "Recovery key copied."))
  }
}

#Preview("Backup") {
  Form { BackupSettingsView(backup: PreviewHelper.model().backup) }.formStyle(.grouped)
}
