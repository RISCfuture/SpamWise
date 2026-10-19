import SwiftUI
import SpamWiseCore
import MailIntegration

/// Mail folders SpamWise filters or learns from: the saved plans, and a plan being added or changed.
struct FolderSettingsView: View {
  let folders: FolderPlansModel
  let shared: SharedStateModel
  let accounts: [MailAccount]
  @State private var selection = ""
  @State private var plan: MailFolderPlan?
  @State private var page = 0
  @Environment(\.dismiss)
  private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        SavedFolderPlansSection(folders: folders, shared: shared, accountName: accountName)
        Section("Add or change a plan") {
          HStack {
            Button("Refresh Folders") { folders.discoverFolders() }
            if folders.plans.isBusy { ProgressView().controlSize(.small) }
            Spacer()
            HelpButton(page: "folders")
          }
          Picker("Folder", selection: $selection) {
            Text("Choose a folder").tag("")
            ForEach(folders.folders) { folder in
              Text("\(accountName(folder.accountID)): \(folder.displayName)").tag(folder.id)
            }
          }
          if let plan {
            FolderPlanFields(plan: Binding(get: { self.plan ?? plan }, set: { self.plan = $0 }))
            HStack {
              Button("Save Plan") { folders.save(plan) }
                .accessibilityIdentifier("folders.save")
              if folders.saving.isBusy { ProgressView().controlSize(.small) }
            }
            OperationStatusView(operation: folders.saving, identifier: "folders.saveStatus")
            if plan.purpose == .filter {
              FolderPreviewControls(folders: folders, plan: plan, page: $page)
            }
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
      folders.saving.status = nil
      plan = folders.folders.first { $0.id == id }.map { folder in
        shared.settings.mailOptions.folderPlans.first { $0.id == id }
          ?? MailFolderPlan(folder: folder)
      }
    }
  }

  private func accountName(_ id: String) -> String {
    accounts.first { $0.id == id }?.name ?? shared.scanHealth[id]?.accountName ?? id
  }
}

/// Every saved plan, including those whose folder Mail no longer lists, with Disable and Remove.
private struct SavedFolderPlansSection: View {
  let folders: FolderPlansModel
  let shared: SharedStateModel
  let accountName: (String) -> String

  var body: some View {
    Section("Saved plans") {
      if folders.statuses.isEmpty {
        Text("No folder plans yet. Choose a folder below to add one.")
          .foregroundStyle(.secondary)
      }
      ForEach(folders.statuses) { status in
        SavedFolderPlanRow(
          folders: folders,
          status: status,
          health: shared.scanHealth[MailSweeper.healthKey(for: status.plan)],
          accountName: accountName(status.plan.folder.accountID)
        )
      }
      OperationStatusView(operation: folders.plans, identifier: "folders.status")
    }
  }
}

/// One saved plan: its folder and purpose, whether it still resolves, and its controls.
private struct SavedFolderPlanRow: View {
  let folders: FolderPlansModel
  let status: FolderPlanStatus
  let health: MailScanHealth?
  let accountName: String
  @State private var confirmingRemoval = false

  private var plan: MailFolderPlan { status.plan }

  var body: some View {
    LabeledContent {
      HStack {
        Toggle(
          "Process automatically",
          isOn: Binding(
            get: { plan.enabled },
            set: { folders.setEnabled($0, planID: plan.id) }
          )
        )
        .labelsHidden()
        .accessibilityLabel(Text("Process \(plan.folder.displayName) automatically"))
        Button("Remove…") { confirmingRemoval = true }
          .accessibilityLabel(Text("Remove the plan for \(plan.folder.displayName)"))
      }
    } label: {
      Text("\(accountName): \(plan.folder.displayName)")
      Text(plan.purpose.localizedTitle)
    }
    .confirmationDialog(
      "Remove the plan for “\(plan.folder.displayName)”?",
      isPresented: $confirmingRemoval,
      titleVisibility: .visible
    ) {
      Button("Remove Plan", role: .destructive) { folders.remove(plan.id) }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("The folder and its mail stay as they are.")
    }
    if status.folderResolves == false {
      WarningLabel(
        "Mail no longer lists this folder, so it isn’t processed. Remove the plan, or restore the folder in Mail."
      )
    } else if let failure = health?.failure {
      WarningLabel(verbatim: failure)
    }
    UnreadableMailView(messageCount: health?.unavailableCount ?? 0)
  }
}

/// Previews one page of a filtered folder; Stop Preview ends only this preview.
private struct FolderPreviewControls: View {
  let folders: FolderPlansModel
  let plan: MailFolderPlan
  @Binding var page: Int

  var body: some View {
    Stepper("Preview page \(page + 1)", value: $page, in: ScanCoordinator.previewPages)
    HStack {
      Button("Preview This Page") {
        folders.previewPage(of: plan.folder, since: plan.startDate, page: page)
      }
      if folders.preview.isBusy {
        ProgressView().controlSize(.small)
        Button("Stop Preview") { folders.preview.cancel() }
      }
    }
    OperationStatusView(operation: folders.preview)
    Text(
      "A preview shows what SpamWise would decide for \(ScanCoordinator.pageLimit) messages at a time, without moving any mail."
    )
    .foregroundStyle(.secondary)
  }
}

private struct FolderPlanFields: View {
  @Binding var plan: MailFolderPlan

  var body: some View {
    Picker("Purpose", selection: $plan.purpose) {
      ForEach(MailFolderPurpose.allCases, id: \.self) { purpose in
        Text(purpose.localizedTitle).tag(purpose)
      }
    }
    if plan.purpose == .filter {
      DatePicker("Filter mail received on or after", selection: $plan.startDate)
    } else {
      Text("Use an empty folder named “\(TrainingFolders.name(for: plan.purpose) ?? "")”.")
      Text(
        "Messages you put in this folder teach SpamWise. Keep it separate from your Junk mailbox and server filters."
      )
      .foregroundStyle(.secondary)
    }
    Toggle("Process this folder automatically", isOn: $plan.enabled)
    Text("If you rename or delete the folder in Mail, SpamWise stops processing it.")
      .foregroundStyle(.secondary)
  }
}

extension MailFolderPurpose {
  var localizedTitle: String {
    switch self {
      case .filter: String(localized: "Filter new mail")
      case .trainGood: String(localized: "Learn Good from placed mail")
      case .trainJunk: String(localized: "Learn Junk from placed mail")
    }
  }
}

#Preview("Saved plans") {
  let model = PreviewHelper.foldersModel()
  FolderSettingsView(folders: model.folders, shared: model.shared, accounts: model.mail.accounts)
}
#Preview("No saved plans") {
  let model = PreviewHelper.model()
  FolderSettingsView(folders: model.folders, shared: model.shared, accounts: model.mail.accounts)
}
#Preview("Filtering plan") {
  Form {
    FolderPlanFields(plan: .constant(.init(folder: .init(accountID: "preview", path: ["Orders"]))))
  }
  .formStyle(.grouped)
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
  .formStyle(.grouped)
}
