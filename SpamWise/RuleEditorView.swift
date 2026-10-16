import SwiftUI
import UniformTypeIdentifiers
import SpamWiseCore

struct RulesDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.json] }
  var data: Data
  init(data: Data) { self.data = data }
  init(configuration: ReadConfiguration) throws {
    guard let data = configuration.file.regularFileContents else {
      throw RuleManagementError.invalidArchive
    }
    self.data = data
  }
  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: data)
  }
}

struct RuleEditorView: View {
  @Bindable var model: AppModel
  @State private var scope: RuleScope = .address
  @State private var disposition: RuleDisposition = .allow
  @State private var value = ""
  @State private var importing = false
  @State private var exporting = false
  @State private var document = RulesDocument(data: Data())
  var body: some View {
    Section("Sender rules") {
      if model.state.rules.isEmpty { Text("No explicit sender rules.").foregroundStyle(.secondary) }
      ForEach(model.state.rules.sorted { $0.id < $1.id }) { rule in
        HStack {
          LabeledContent("\(rule.scope.localizedTitle): \(rule.value)") {
            Text(rule.disposition.localizedTitle)
              .accessibilityIdentifier("settings.rule.\(rule.scope.rawValue).\(rule.value)")
          }
          Button("Edit") {
            scope = rule.scope; value = rule.value; disposition = rule.disposition
          }
          .accessibilityLabel("Edit rule for \(rule.value)")
          Button("Remove", role: .destructive) { model.removeRule(rule.id) }
            .accessibilityLabel("Remove rule for \(rule.value)")
        }
      }
      Picker("Rule scope", selection: $scope) {
        Text("Email address").tag(RuleScope.address)
        Text("Entire domain").tag(RuleScope.domain)
      }.accessibilityIdentifier("rules.scope")
      TextField("Address or registrable domain", text: $value).accessibilityIdentifier(
        "rules.value"
      )
      Picker("Action", selection: $disposition) {
        Text("Allow").tag(RuleDisposition.allow); Text("Block").tag(RuleDisposition.block)
      }.accessibilityIdentifier("rules.action")
      Text("Address rules take precedence over domain rules and trusted relationships.").font(
        .caption
      )
      HStack {
        Button("Save rule") { model.saveRule(scope: scope, value: value, disposition: disposition) }
          .disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.busy)
          .accessibilityIdentifier("rules.save")
        Button("Import rules…") { importing = true }.disabled(model.busy)
        Button("Export rules…") {
          do {
            document = RulesDocument(data: try RuleManagement.exportRules(model.state.rules))
            exporting = true
          } catch { model.status = String(localized: "Rules could not be exported.") }
        }
      }
      Text(
        "Import merges rules and replaces matching scopes; other rules remain. Exports contain no messages or keys."
      )
      .font(.caption)
    }
    .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
      switch result {
        case .success(let url): model.importRules(url)
        case .failure: model.status = String(localized: "Rule import was cancelled or unavailable.")
      }
    }
    .fileExporter(
      isPresented: $exporting,
      document: document,
      contentType: .json,
      defaultFilename: "SpamWise-rules"
    ) {
      if case .failure = $0 { model.status = String(localized: "Rules could not be exported.") }
    }
  }
}

extension AppModel {
  func saveRule(scope: RuleScope, value: String, disposition: RuleDisposition) {
    run { [self] in
      guard let store else { throw IntegrationError.unavailable }
      try await RuleManagement.save(
        scope: scope,
        value: value,
        disposition: disposition,
        store: store
      )
      status = String(localized: "Rule saved. Pending classifications were invalidated.")
    }
  }
  func removeRule(_ id: String) {
    run { [self] in
      guard let store else { throw IntegrationError.unavailable }
      try await RuleManagement.remove(id: id, store: store)
      status = String(localized: "Rule removed.")
    }
  }
  func importRules(_ url: URL) {
    run { [self] in
      guard let store else { throw IntegrationError.unavailable }
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      let file = try FileHandle(forReadingFrom: url)
      defer { try? file.close() }
      let data = try file.read(upToCount: 2_000_001) ?? Data()
      try await RuleManagement.importRules(data, store: store)
      status = String(localized: "Rules imported. Pending classifications were invalidated.")
    }
  }
}

#Preview { Form { RuleEditorView(model: AppModel(preview: true)) }.formStyle(.grouped) }
