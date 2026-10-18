import SwiftUI
import SpamWiseCore
import MailIntegration

struct FolderSettingsView: View {
  let folders: FolderPlansModel
  let shared: SharedStateModel
  let accounts: [MailAccount]
  @State private var selection = ""
  @State private var plan: MailFolderPlan?
  @State private var page = 0
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section("Mail.app folders") {
          HStack {
            Button("Refresh folders") { folders.discoverFolders() }
            if folders.plans.isBusy { ProgressView().controlSize(.small) }
          }
          Picker("Folder", selection: $selection) {
            Text("Choose folder").tag("")
            ForEach(folders.folders) { folder in
              Text("\(accountName(folder.accountID)): \(folder.displayName)").tag(folder.id)
            }
          }
          if let plan {
            FolderPlanFields(plan: Binding(get: { self.plan ?? plan }, set: { self.plan = $0 }))
            Button("Save folder plan") { folders.save(plan) }
            OperationStatusView(operation: folders.plans)
            if let health = shared.scanHealth[MailSweeper.healthKey(for: plan)] {
              FolderHealthView(health: health)
            }
            if plan.purpose == .filter {
              FolderPreviewControls(folders: folders, plan: plan, page: $page)
            }
          } else {
            OperationStatusView(operation: folders.plans)
          }
        }
      }
      .formStyle(.grouped)
      .navigationTitle("Folders")
      .toolbar { DoneToolbarItem(dismiss: dismiss, identifier: "folders.done") }
    }
    .frame(minWidth: 600, minHeight: 540)
    .onChange(of: selection) { _, id in
      page = 0
      plan = folders.folders.first { $0.id == id }.map { folder in
        shared.settings.mailOptions.folderPlans.first { $0.id == id }
          ?? MailFolderPlan(folder: folder)
      }
    }
  }

  private func accountName(_ id: String) -> String {
    accounts.first { $0.id == id }?.name ?? id
  }
}

private struct FolderHealthView: View {
  let health: MailScanHealth

  var body: some View {
    if let date = health.lastSuccess {
      LabeledContent("Last successful page", value: date.formatted())
    }
    UnreadableMailView(count: health.unavailableCount)
    if let failure = health.failure {
      StatusLabel(status: .failure(OperationFailure(message: failure)))
    }
  }
}

/// Previews one page of a filtered folder; Stop Preview ends only this preview.
private struct FolderPreviewControls: View {
  let folders: FolderPlansModel
  let plan: MailFolderPlan
  @Binding var page: Int

  var body: some View {
    Stepper("Preview page: \(page + 1)", value: $page, in: 0...1000)
    HStack {
      Button("Preview this page") {
        folders.previewPage(of: plan.folder, since: plan.startDate, page: page)
      }
      if folders.preview.isBusy {
        ProgressView().controlSize(.small)
        Button("Stop Preview") { folders.preview.cancel() }
      }
    }
    OperationStatusView(operation: folders.preview)
    Text(
      "Previews recompute decisions without replaying mail actions. Each page contains up to 20 messages."
    )
    .foregroundStyle(.secondary)
  }
}

private struct FolderPlanFields: View {
  @Binding var plan: MailFolderPlan

  var body: some View {
    Picker("Purpose", selection: $plan.purpose) {
      Text("Filter new mail").tag(MailFolderPurpose.filter)
      Text("Train Good from deliberate placements").tag(MailFolderPurpose.trainGood)
      Text("Train Junk from deliberate placements").tag(MailFolderPurpose.trainJunk)
    }
    if plan.purpose == .filter {
      DatePicker("Received on or after", selection: $plan.startDate)
    } else {
      Text("Use an empty dedicated folder named \(TrainingFolders.name(for: plan.purpose) ?? "").")
      Text(
        "Place mail here only to train SpamWise. Keep server filters and ordinary Junk separate."
      )
      .foregroundStyle(.secondary)
    }
    Toggle("Process this folder automatically", isOn: $plan.enabled)
    Text(
      "Renamed or missing folders stop processing. Account selection, Pause and dry run still apply."
    )
    .foregroundStyle(.secondary)
  }
}

#Preview("Folder selection") {
  let model = PreviewHelper.model()
  FolderSettingsView(folders: model.folders, shared: model.shared, accounts: model.mail.accounts)
}
#Preview("Filtering plan") {
  Form {
    FolderPlanFields(plan: .constant(.init(folder: .init(accountID: "preview", path: ["Orders"]))))
  }
}
#Preview("Training plan") {
  Form {
    FolderPlanFields(
      plan: .constant(
        .init(
          folder: .init(accountID: "preview", path: ["SpamWise Train Good"]),
          purpose: .trainGood
        )
      )
    )
  }
}
