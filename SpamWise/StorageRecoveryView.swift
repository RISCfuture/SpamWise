import SwiftUI
import UniformTypeIdentifiers
import SpamWiseCore

/**
 Shown instead of Activity when some saved data couldn't be read: restore a backup, or keep the
 current state. Either way the set-aside data can be saved first, for support.
 */
struct StorageRecoveryView: View {
  let recovery: StorageRecoveryModel
  @State private var confirmingKeep = false
  @State private var exporting = false
  @State private var document: BackupDocument?
  @State private var fileStatus: OperationStatus?

  var body: some View {
    Form {
      Section {
        WarningLabel("Some SpamWise data couldn’t be read")
          .font(.headline)
        Text(
          """
          SpamWise set it aside and is running with everything else. Mail stays unchanged. Restore \
          a backup to bring the data back, or keep the current settings.
          """
        )
      }
      Section("Set-aside data") {
        ForEach(recovery.entries, id: \.source) { entry in
          LabeledContent(entry.localizedSource) {
            Text(
              """
              \(entry.byteCount.formatted(.byteCount(style: .file))) · \
              \(entry.date.formatted(date: .abbreviated, time: .shortened))
              """
            )
          }
        }
        Button("Save a Copy…") { prepareExport() }
          .fileExporter(
            isPresented: $exporting,
            document: document,
            contentType: .json,
            defaultFilename: String(localized: "SpamWise Set-Aside Data.json")
          ) { fileStatus = ExportResult.status(of: $0, failure: "The copy couldn’t be saved.") }
        StatusLabel(status: fileStatus)
      }
      Section("Restore from backup") {
        BackupRestoreControls(isBusy: recovery.operation.isBusy) {
          recovery.restore(from: $0, recoveryKey: $1)
        }
      }
      Section {
        Button("Keep Current Settings…") { confirmingKeep = true }
          .disabled(recovery.operation.isBusy)
          .accessibilityIdentifier("recovery.keep")
          .confirmationDialog(
            "Keep the current settings?",
            isPresented: $confirmingKeep,
            titleVisibility: .visible
          ) {
            Button("Discard Set-Aside Data", role: .destructive) { recovery.keepCurrentState() }
            Button("Cancel", role: .cancel) {}
          } message: {
            Text(
              "SpamWise discards the data it couldn’t read. Save a copy first if you might need it."
            )
          }
        OperationStatusView(operation: recovery.operation, identifier: "recovery.status")
      }
    }
    .formStyle(.grouped)
    .navigationTitle("Recover SpamWise Data")
    .frame(minWidth: 560, minHeight: 460)
  }

  private func prepareExport() {
    fileStatus = nil
    recovery.exportPreservedData { data in
      document = BackupDocument(data: data)
      exporting = true
    }
  }
}

#Preview("Recovery") {
  let model = PreviewHelper.recoveryModel()
  StorageRecoveryView(recovery: model.recovery)
}
