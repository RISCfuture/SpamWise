import SwiftUI
import UniformTypeIdentifiers
import SpamWiseCore

struct BackupSettingsView: View {
  let model: AppModel
  @State private var recoveryKey = ""
  @State private var includeContent = false
  @State private var exporting = false
  @State private var importing = false
  @State private var confirmingRestore = false
  @State private var pendingURL: URL?
  @State private var document: RulesDocument?

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
      }.disabled(recoveryKey.isEmpty || model.busy)
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
    ) {
      if case .failure = $0 { model.status = String(localized: "Backup export failed.") }
    }
    .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) {
      switch $0 {
        case .success(let url): pendingURL = url; confirmingRestore = true
        case .failure: model.status = String(localized: "Backup import failed.")
      }
    }
    .confirmationDialog(
      "Replace rules, policy and learning from this backup?",
      isPresented: $confirmingRestore
    ) {
      Button("Restore and pause filtering", role: .destructive) { restore() }
    }
  }
  private func prepareExport() {
    let key = recoveryKey, content = includeContent
    model.run {
      guard let store = model.store else { throw IntegrationError.unavailable }
      document = RulesDocument(
        data: try await StateBackup.export(store: store, recoveryKey: key, includeContent: content)
      )
      exporting = true
    }
  }
  private func restore() {
    guard let url = pendingURL else { return }
    let key = recoveryKey
    model.run {
      guard let store = model.store else { throw IntegrationError.unavailable }
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      let file = try FileHandle(forReadingFrom: url)
      defer { try? file.close() }
      let data = try file.read(upToCount: 64 * 1024 * 1024 + 1) ?? Data()
      try await StateBackup.restore(data, recoveryKey: key, store: store)
      model.status = String(
        localized:
          "Backup restored. Filtering is paused; validate accounts before resuming actions."
      )
    }
  }
}

#Preview("Backup") { Form { BackupSettingsView(model: PreviewHelper.model()) } }
