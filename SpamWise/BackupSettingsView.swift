import SwiftUI
import UniformTypeIdentifiers
import SpamWiseCore

struct BackupSettingsView: View {
  let backup: BackupModel
  @State private var recoveryKey = ""
  @State private var includeContent = false
  @State private var exporting = false
  @State private var importing = false
  @State private var confirmingRestore = false
  @State private var pendingURL: URL?
  @State private var document: RulesDocument?
  @State private var fileStatus: OperationStatus?

  var body: some View {
    DisclosureGroup("Backup and restore") {
      Text(
        "Backs up rules, policy, corrections and learning. Keep the recovery key separately; it cannot be recovered."
      )
      .foregroundStyle(.secondary)
      SecureField("Recovery key", text: $recoveryKey).accessibilityIdentifier("backup.key")
      Button("Generate recovery key") { recoveryKey = StateBackup.recoveryKey() }
      Button("Copy recovery key") {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(recoveryKey, forType: .string)
      }.disabled(recoveryKey.isEmpty)
      Toggle("Include retained reviewed message text", isOn: $includeContent)
      HStack {
        Button("Export encrypted backup") { prepareExport() }
        Button("Restore backup…") { importing = true }
        if backup.operation.isBusy { ProgressView().controlSize(.small) }
      }.disabled(recoveryKey.isEmpty)
      OperationStatusView(operation: backup.operation)
      StatusLabel(status: fileStatus)
      Text(
        "Restore replaces learning, pauses filtering and clears validation. Credentials and spending are preserved."
      )
      .foregroundStyle(.secondary)
    }
    .fileExporter(
      isPresented: $exporting,
      document: document,
      contentType: .data,
      defaultFilename: "SpamWise.spamwisebackup"
    ) { fileStatus = ExportResult.status(of: $0, failure: "Backup export failed.") }
    .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) {
      switch $0 {
        case .success(let url):
          fileStatus = nil; pendingURL = url; confirmingRestore = true
        case .failure:
          fileStatus = .failure(
            OperationFailure(message: String(localized: "Backup import failed."))
          )
      }
    }
    .confirmationDialog(
      "Replace rules, policy and learning from this backup?",
      isPresented: $confirmingRestore
    ) {
      Button("Restore and pause filtering", role: .destructive) {
        if let pendingURL { backup.restore(from: pendingURL, recoveryKey: recoveryKey) }
      }
    }
  }

  private func prepareExport() {
    fileStatus = nil
    backup.export(recoveryKey: recoveryKey, includeContent: includeContent) { data in
      document = RulesDocument(data: data); exporting = true
    }
  }
}

#Preview("Backup") { Form { BackupSettingsView(backup: PreviewHelper.model().backup) } }
