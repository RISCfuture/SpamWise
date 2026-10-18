import SwiftUI
import UniformTypeIdentifiers
import SpamWiseCore

struct RuleEditorView: View {
  let rules: RulesModel
  let shared: SharedStateModel
  @State private var selection: String?
  @State private var editor: RuleEditing?
  @State private var importing = false
  @State private var exporting = false
  @State private var showsContentRules = false
  @State private var document = RulesDocument(data: Data())
  @State private var transferStatus: OperationStatus?

  private var selectedRule: SenderRule? { shared.state.rules.first { $0.id == selection } }
  private var sortedRules: [SenderRule] { shared.state.rules.sorted { $0.value < $1.value } }

  var body: some View {
    VStack(alignment: .leading) {
      Text("Address rules take precedence over domain rules and trusted relationships.")
        .foregroundStyle(.secondary).accessibilityIdentifier("settings.rules.content")
      SenderRuleTable(rules: sortedRules, selection: $selection)
      HStack {
        Button("Add rule") { editor = RuleEditing(rule: nil) }
          .accessibilityIdentifier("rules.add")
        Button("Edit") { editor = RuleEditing(rule: selectedRule) }
          .disabled(selectedRule == nil).accessibilityIdentifier("rules.edit")
        Button("Remove", role: .destructive) {
          if let selectedRule { rules.removeSenderRule(selectedRule.id); selection = nil }
        }.disabled(selectedRule == nil).accessibilityIdentifier("rules.remove")
        if rules.senderRules.isBusy { ProgressView().controlSize(.small) }
        Spacer()
        Menu("Transfer rules") {
          Button("Import rules…") { importing = true }
          Button("Export rules…") { exportRules() }.disabled(sortedRules.isEmpty)
        }
      }
      OperationStatusView(operation: rules.senderRules)
      StatusLabel(status: transferStatus)
      Button("Content rules…") { showsContentRules = true }
    }.padding()
      .sheet(item: $editor) { editing in RuleFormView(rules: rules, rule: editing.rule) }
      .sheet(isPresented: $showsContentRules) {
        ContentRuleEditorView(rules: rules, shared: shared)
      }
      .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
        if case .success(let url) = result { rules.importSenderRules(from: url) }
      }
      .fileExporter(
        isPresented: $exporting,
        document: document,
        contentType: .json,
        defaultFilename: "SpamWise-rules"
      ) { transferStatus = ExportResult.status(of: $0, failure: "Rules could not be exported.") }
  }

  private func exportRules() {
    do {
      document = RulesDocument(data: try rules.exportedSenderRules())
      exporting = true
    } catch {
      transferStatus = .failure(OperationFailure(error))
    }
  }
}

/// The rule a form edits, or a new rule.
private struct RuleEditing: Identifiable {
  let id = UUID()
  let rule: SenderRule?
}

private struct SenderRuleTable: View {
  let rules: [SenderRule]
  @Binding var selection: String?

  var body: some View {
    Table(rules, selection: $selection) {
      TableColumn("Sender", value: \.value)
      TableColumn("Scope") { rule in Text(rule.scope.localizedTitle) }.width(120)
      TableColumn("Action") { rule in
        Text(rule.disposition.localizedTitle)
          .accessibilityIdentifier("settings.rule.\(rule.scope.rawValue).\(rule.value)")
      }.width(80)
    }
    .overlay {
      if rules.isEmpty {
        ContentUnavailableView(
          "No sender rules",
          systemImage: "line.3.horizontal.decrease",
          description: Text("Add an address or domain to always allow or block its mail.")
        )
      }
    }
  }
}

#Preview("Rules") {
  let model = PreviewHelper.model()
  RuleEditorView(rules: model.rules, shared: model.shared)
}
#Preview("Empty rules") {
  let model = PreviewHelper.model(empty: true)
  RuleEditorView(rules: model.rules, shared: model.shared)
}
