import SwiftUI
import SpamWiseCore

/// Backup or restore alone, as File › Export Backup and Restore from Backup present it.
struct BackupSheet: View {
  let backup: BackupModel
  let task: BackupTask
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section {
          switch task {
            case .export: BackupExportView(backup: backup)
            case .restore:
              BackupRestoreControls(isBusy: backup.operation.isBusy) {
                backup.restore(from: $0, recoveryKey: $1)
              }
          }
          OperationStatusView(operation: backup.operation, identifier: "backup.status")
        }
      }
      .formStyle(.grouped)
      .navigationTitle(task == .export ? Text("Export Backup") : Text("Restore from Backup"))
      .toolbar { DoneToolbarItem(dismiss: dismiss, identifier: "backup.done") }
    }
    .frame(minWidth: 520, minHeight: 360)
  }
}

/// Which half of backup a sheet shows.
enum BackupTask: String, Equatable {
  case export, restore
}

/// File › Export Backup and Restore from Backup, each opening its half of backup in Activity.
struct BackupCommands: Commands {
  let router: ActivityRouter
  let shared: SharedStateModel
  @Environment(\.openWindow) private var openWindow

  var body: some Commands {
    CommandGroup(after: .importExport) {
      Group {
        Button("Export Backup…") { show(.export) }
        Button("Restore from Backup…") { show(.restore) }
      }
      .disabled(shared.store == nil || !shared.settings.onboardingComplete)
    }
  }

  private func show(_ task: BackupTask) {
    openWindow(id: "activity")
    router.present(.backup(task))
  }
}

#Preview("Export sheet") { BackupSheet(backup: PreviewHelper.model().backup, task: .export) }
#Preview("Restore sheet") { BackupSheet(backup: PreviewHelper.model().backup, task: .restore) }
