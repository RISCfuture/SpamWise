import SwiftUI
import SpamWiseCore
import MailIntegration

struct FolderSettingsView: View {
  let model: AppModel
  @State private var selection = ""
  @State private var plan: MailFolderPlan?
  @State private var page = 0
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack {
      Form {
        Section("Mail.app folders") {
          Button("Refresh folders") { model.discoverFolders() }.disabled(model.busy)
          Picker("Folder", selection: $selection) {
            Text("Choose folder").tag("")
            ForEach(model.folders) { folder in
              Text("\(accountName(folder.accountID)): \(folder.displayName)").tag(folder.id)
            }
          }
          if let plan {
            FolderPlanFields(plan: Binding(get: { self.plan ?? plan }, set: { self.plan = $0 }))
            Button("Save folder plan") { model.saveFolderPlan(plan) }.disabled(model.busy)
            if let health = model.scanHealth["folder:" + plan.id] {
              if let date = health.lastSuccess {
                LabeledContent("Last successful page", value: date.formatted())
              }
              UnreadableMailView(count: health.unavailableCount)
              if let failure = health.failure { Text(failure).textSelection(.enabled) }
            }
            if plan.purpose == .filter {
              Stepper("Preview page: \(page + 1)", value: $page, in: 0...1000)
              Button("Preview this page") {
                model.refilterFolder(plan.folder, since: plan.startDate, offset: page * 20)
              }.disabled(model.busy)
              Text(
                "Previews recompute decisions without replaying mail actions. Each page contains up to 20 messages."
              )
              .foregroundStyle(.secondary)
            }
          }
        }
        if !model.status.isEmpty { Text(model.status).textSelection(.enabled) }
      }.formStyle(.grouped)
      HStack {
        if model.busy { Button("Cancel") { model.cancel() } }
        Spacer()
        Button("Done") { dismiss() }
      }.padding()
    }.frame(minWidth: 600, minHeight: 540)
      .onChange(of: selection) { _, id in
        page = 0
        plan = model.folders.first { $0.id == id }.map { folder in
          model.state.settings.mailOptions.folderPlans.first { $0.id == id }
            ?? MailFolderPlan(folder: folder)
        }
      }
  }
  private func accountName(_ id: String) -> String {
    model.accounts.first { $0.id == id }?.name ?? id
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

#Preview("Folder selection") { FolderSettingsView(model: PreviewHelper.model()) }
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
