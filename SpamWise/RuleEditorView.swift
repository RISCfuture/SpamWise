import SwiftUI
import UniformTypeIdentifiers
import SpamWiseCore

/// The Rules settings tab: sender rules and content rules, one kind at a time.
struct RuleEditorView: View {
  let rules: RulesModel
  let shared: SharedStateModel
  @State private var kind = RuleKind.sender

  var body: some View {
    VStack(alignment: .leading) {
      Picker("Rules", selection: $kind) {
        Text("Sender Rules").tag(RuleKind.sender)
        Text("Content Rules").tag(RuleKind.content)
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .fixedSize()
      .frame(maxWidth: .infinity)
      .accessibilityIdentifier("rules.kind")
      switch kind {
        case .sender: SenderRulesPane(rules: rules, shared: shared)
        case .content: ContentRulesPane(rules: rules, shared: shared)
      }
    }
    .padding()
  }
}

/// The kinds of rule the Rules tab lists.
private enum RuleKind: Hashable {
  case sender, content
}

/// Sender rules: a table with add, edit, remove and transfer.
private struct SenderRulesPane: View {
  let rules: RulesModel
  let shared: SharedStateModel
  @State private var selection: Set<SenderRule.ID> = []
  @State private var editor: RuleEditing?
  @State private var removing: Set<SenderRule.ID> = []
  @State private var importing = false
  @State private var exporting = false
  @State private var document = RulesDocument(data: Data())
  @State private var transferStatus: OperationStatus?

  private var sortedRules: [SenderRule] { shared.state.rules.sorted { $0.value < $1.value } }

  var body: some View {
    VStack(alignment: .leading) {
      Text(
        "A rule for an address wins over a rule for its domain. Allow rules apply only to mail SpamWise can verify."
      )
      .foregroundStyle(.secondary).accessibilityIdentifier("settings.rules.content")
      SenderRuleTable(
        rules: sortedRules,
        selection: $selection,
        edit: edit,
        remove: { removing = $0 }
      )
      HStack {
        Button("Add Rule…") { editor = RuleEditing(rule: nil) }
          .accessibilityIdentifier("rules.add")
        Button("Edit…") { edit(selection) }
          .disabled(selection.count != 1).accessibilityIdentifier("rules.edit")
        Button("Remove…", role: .destructive) { removing = selection }
          .disabled(selection.isEmpty).accessibilityIdentifier("rules.remove")
        if rules.senderRules.isBusy { ProgressView().controlSize(.small) }
        Spacer()
        Menu("Transfer Rules") {
          Button("Import Rules…") { importing = true }
          Button("Export Rules…") { exportRules() }.disabled(sortedRules.isEmpty)
        }
        .fixedSize()
      }
      OperationStatusView(operation: rules.senderRules)
      StatusLabel(status: transferStatus)
    }
    .sheet(item: $editor) { editing in RuleFormView(rules: rules, rule: editing.rule) }
    .confirmationDialog(
      removalTitle,
      isPresented: Binding(get: { !removing.isEmpty }, set: { if !$0 { removing = [] } })
    ) {
      Button("Remove", role: .destructive) {
        rules.removeSenderRules(removing)
        selection.subtract(removing)
      }
      .accessibilityIdentifier("rules.remove.confirm")
    } message: {
      Text(
        "SpamWise decides new mail from these senders without the rule. Mail already filtered stays where it is."
      )
    }
    .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
      if case .success(let url) = result { rules.importSenderRules(from: url) }
    }
    .fileExporter(
      isPresented: $exporting,
      document: document,
      contentType: .json,
      defaultFilename: "SpamWise-rules"
    ) { transferStatus = ExportResult.status(of: $0, failure: "Rules couldn’t be exported.") }
  }

  private var removalTitle: String {
    guard removing.count == 1, let id = removing.first,
      let rule = shared.state.rules.first(where: { $0.id == id })
    else { return String(localized: "Remove \(removing.count) rules?") }
    return String(localized: "Remove the rule for \(rule.value)?")
  }

  private func edit(_ ids: Set<SenderRule.ID>) {
    guard ids.count == 1, let rule = shared.state.rules.first(where: { ids.contains($0.id) })
    else { return }
    editor = RuleEditing(rule: rule)
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
  @Binding var selection: Set<SenderRule.ID>
  let edit: (Set<SenderRule.ID>) -> Void
  let remove: (Set<SenderRule.ID>) -> Void

  var body: some View {
    Table(rules, selection: $selection) {
      TableColumn("Sender", value: \.value)
      TableColumn("Applies To") { rule in Text(rule.scope.localizedTitle) }.width(120)
      TableColumn("Action") { rule in
        Text(rule.disposition.localizedTitle)
          .accessibilityIdentifier("settings.rule.\(rule.scope.rawValue).\(rule.value)")
      }.width(80)
    }
    .contextMenu(forSelectionType: SenderRule.ID.self) { ids in
      if ids.count == 1 { Button("Edit…") { edit(ids) } }
      if !ids.isEmpty { Button("Remove…", role: .destructive) { remove(ids) } }
    } primaryAction: { ids in
      edit(ids)
    }
    .onDeleteCommand { if !selection.isEmpty { remove(selection) } }
    .overlay {
      if rules.isEmpty {
        ContentUnavailableView(
          "No Sender Rules",
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
