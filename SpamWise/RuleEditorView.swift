import SwiftUI
import UniformTypeIdentifiers
import SpamWiseCore

struct RuleEditorView: View {
  @Bindable var model: AppModel
  @State private var selection: String?
  @State private var editingRule: SenderRule?
  @State private var showingEditor = false
  @State private var importing = false
  @State private var exporting = false
  @State private var showsContentRules = false
  @State private var document = RulesDocument(data: Data())

  private var selectedRule: SenderRule? { model.state.rules.first { $0.id == selection } }
  private var sortedRules: [SenderRule] { model.state.rules.sorted { $0.value < $1.value } }

  var body: some View {
    VStack(alignment: .leading) {
      Text("Address rules take precedence over domain rules and trusted relationships.")
        .foregroundStyle(.secondary).accessibilityIdentifier("settings.rules.content")
      Table(sortedRules, selection: $selection) {
        TableColumn("Sender", value: \.value)
        TableColumn("Scope") { rule in Text(rule.scope.localizedTitle) }.width(120)
        TableColumn("Action") { rule in
          Text(rule.disposition.localizedTitle)
            .accessibilityIdentifier("settings.rule.\(rule.scope.rawValue).\(rule.value)")
        }.width(80)
      }
      .overlay {
        if sortedRules.isEmpty {
          ContentUnavailableView(
            "No sender rules",
            systemImage: "line.3.horizontal.decrease",
            description: Text("Add an address or domain to always allow or block its mail.")
          )
        }
      }
      HStack {
        Button("Add rule") {
          editingRule = nil; showingEditor = true
        }
        .accessibilityIdentifier("rules.add")
        Button("Edit") {
          editingRule = selectedRule; showingEditor = true
        }
        .disabled(selectedRule == nil).accessibilityIdentifier("rules.edit")
        Button("Remove", role: .destructive) {
          if let selectedRule { model.removeRule(selectedRule.id); selection = nil }
        }.disabled(selectedRule == nil).accessibilityIdentifier("rules.remove")
        Spacer()
        Menu("Transfer rules") {
          Button("Import rules…") { importing = true }
          Button("Export rules…") { exportRules() }.disabled(sortedRules.isEmpty)
        }
      }.disabled(model.busy)
      Button("Content rules…") { showsContentRules = true }
    }.padding()
      .sheet(isPresented: $showingEditor) { RuleFormView(model: model, rule: editingRule) }
      .sheet(isPresented: $showsContentRules) { ContentRuleEditorView(model: model) }
      .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
        switch result {
          case .success(let url): model.importRules(url)
          case .failure: break
        }
      }
      .fileExporter(
        isPresented: $exporting,
        document: document,
        contentType: .json,
        defaultFilename: "SpamWise-rules"
      ) { result in
        if case .failure = result {
          model.status = String(localized: "Rules could not be exported.")
        }
      }
  }

  private func exportRules() {
    do {
      document = RulesDocument(data: try RuleManagement.exportRules(model.state.rules))
      exporting = true
    } catch { model.status = AppModel.describe(error) }
  }
}

#Preview("Rules") { RuleEditorView(model: PreviewHelper.model()) }
#Preview("Empty rules") { RuleEditorView(model: PreviewHelper.model(empty: true)) }
