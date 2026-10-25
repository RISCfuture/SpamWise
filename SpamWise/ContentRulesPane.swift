import SwiftUI
import SpamWiseCore
import UniformTypeIdentifiers

/// Content rules: a table with inline on/off switches, add, edit, remove and transfer.
struct ContentRulesPane: View {
  let rules: RulesModel
  let shared: SharedStateModel
  @State private var selection: Set<ContentRule.ID> = []
  @State private var editor: ContentRuleEditing?
  @State private var removing: Set<ContentRule.ID> = []
  @State private var importing = false
  @State private var exporting = false
  @State private var archive: RulesDocument?
  @State private var exportStatus: OperationStatus?

  private var contentRules: [ContentRule] {
    shared.state.contentRules.sorted { $0.updatedAt > $1.updatedAt }
  }

  var body: some View {
    VStack(alignment: .leading) {
      Text("Content rules apply after sender rules. When several match, the newest one decides.")
        .foregroundStyle(.secondary)
      ContentRuleTable(
        rules: rules,
        shared: shared,
        contentRules: contentRules,
        selection: $selection,
        edit: edit,
        remove: { removing = $0 }
      )
      HStack {
        Button("Add Rule…") { editor = ContentRuleEditing(rule: ContentRule(), isNew: true) }
          .accessibilityIdentifier("contentRules.add")
        Button("Edit…") { edit(selection) }.disabled(selection.count != 1)
        Button("Remove…", role: .destructive) { removing = selection }
          .disabled(selection.isEmpty)
        if rules.contentRules.isBusy { ProgressView().controlSize(.small) }
        Spacer()
        Menu("Transfer Rules") {
          Button("Import Content Rules…") { importing = true }
          Button("Export Content Rules…") { exportRules() }.disabled(contentRules.isEmpty)
        }
        .fixedSize()
      }
      OperationStatusView(operation: rules.contentRules)
      StatusLabel(status: exportStatus)
    }
    .sheet(item: $editor) { editing in
      ContentRuleFormView(rules: rules, rule: editing.rule, isNew: editing.isNew)
    }
    .confirmationDialog(
      "Remove \(removing.count) content rules?",
      isPresented: Binding(get: { !removing.isEmpty }, set: { if !$0 { removing = [] } })
    ) {
      Button("Remove", role: .destructive) {
        rules.removeContentRules(removing)
        selection.subtract(removing)
      }
    } message: {
      Text("Mail already filtered stays where it is.")
    }
    .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
      if case .success(let url) = result { rules.importContentRules(from: url) }
    }
    .fileExporter(
      isPresented: $exporting,
      document: archive,
      contentType: .json,
      defaultFilename: "SpamWise-content-rules"
    ) { exportStatus = ExportResult.status(of: $0, failure: "Content rules couldn’t be exported.") }
  }

  private func edit(_ ids: Set<ContentRule.ID>) {
    guard ids.count == 1, let rule = shared.state.contentRules.first(where: { ids.contains($0.id) })
    else { return }
    editor = ContentRuleEditing(rule: rule, isNew: false)
  }

  private func exportRules() {
    do {
      archive = RulesDocument(data: try rules.exportedContentRules())
      exporting = true
    } catch {
      exportStatus = .failure(OperationFailure(error))
    }
  }
}

/// The content rule a form edits.
private struct ContentRuleEditing: Identifiable {
  let id = UUID()
  let rule: ContentRule
  let isNew: Bool
}

private struct ContentRuleTable: View {
  let rules: RulesModel
  let shared: SharedStateModel
  let contentRules: [ContentRule]
  @Binding var selection: Set<ContentRule.ID>
  let edit: (Set<ContentRule.ID>) -> Void
  let remove: (Set<ContentRule.ID>) -> Void

  var body: some View {
    Table(contentRules, selection: $selection) {
      TableColumn("On") { rule in
        Toggle(
          "Use this rule",
          isOn: Binding(get: { rule.enabled }, set: { rules.setContentRule(rule.id, enabled: $0) })
        )
        .labelsHidden()
        .accessibilityLabel(Text("Use rule \(rule.pattern)"))
      }.width(36)
      TableColumn("Field") { Text($0.field.localizedTitle) }
      TableColumn("Match") { Text($0.operation.localizedTitle) }
      TableColumn("Expression", value: \.pattern)
      TableColumn("Action") { Text($0.disposition.localizedTitle) }
      TableColumn("Matches") { Text(shared.state.contentRuleHits[$0.id, default: 0].formatted()) }
      TableColumn("Couldn’t Check") {
        Text(shared.state.contentRuleSkips[$0.id, default: 0].formatted())
          .help(
            """
            Messages this rule couldn’t be checked against because its expression is invalid or \
            took too long. The rule doesn’t match those messages.
            """
          )
      }
    }
    .contextMenu(forSelectionType: ContentRule.ID.self) { ids in
      if ids.count == 1 { Button("Edit…") { edit(ids) } }
      if !ids.isEmpty { Button("Remove…", role: .destructive) { remove(ids) } }
    } primaryAction: { ids in
      edit(ids)
    }
    .onDeleteCommand { if !selection.isEmpty { remove(selection) } }
    .overlay {
      if contentRules.isEmpty {
        ContentUnavailableView(
          "No Content Rules",
          systemImage: "text.magnifyingglass",
          description: Text(
            "Add a rule to allow or block mail whose subject, body or headers match an expression."
          )
        )
      }
    }
  }
}

/// Adds or edits one content rule; it closes only once the rule is saved.
struct ContentRuleFormView: View {
  let rules: RulesModel
  @State private var rule: ContentRule
  let isNew: Bool
  @State private var saving = TrackedOperation()
  @State private var testing = TrackedOperation()
  @Environment(\.dismiss)
  private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Picker("Field", selection: $rule.field) {
          ForEach(ContentRuleField.allCases, id: \.self) { Text($0.localizedTitle).tag($0) }
        }
        Picker("Match", selection: $rule.operation) {
          ForEach(ContentRuleOperator.allCases, id: \.self) { Text($0.localizedTitle).tag($0) }
        }
        TextField(
          "Expression",
          text: $rule.pattern,
          prompt: Text(verbatim: rule.operation.examplePattern)
        )
        Picker("Action", selection: $rule.disposition) {
          Text("Allow").tag(RuleDisposition.allow)
          Text("Block").tag(RuleDisposition.block)
        }
        Toggle("Use this rule", isOn: $rule.enabled)
        TextField("Notes", text: $rule.note, prompt: Text("Optional"), axis: .vertical)
        Text("Matching ignores capitalization. A rule that takes too long to check doesn’t match.")
          .foregroundStyle(.secondary)
        HStack {
          Button("Test with Message Selected in Mail") { test() }
          if testing.isBusy { ProgressView().controlSize(.small) }
        }
        OperationStatusView(operation: testing)
        OperationStatusView(operation: saving)
      }
      .formStyle(.grouped)
      .navigationTitle(isNew ? "Add Content Rule" : "Edit Content Rule")
      .toolbar {
        ConfirmationToolbarItems(
          confirmTitle: "Save",
          canConfirm: (try? ContentRules.validate(rule)) != nil && !saving.isBusy,
          cancel: { dismiss() },
          confirm: save
        )
      }
    }
    .frame(minWidth: 480, idealWidth: 520)
  }

  init(rules: RulesModel, rule: ContentRule, isNew: Bool) {
    self.rules = rules
    _rule = State(initialValue: rule)
    self.isNew = isNew
  }

  private func save() {
    let draft = rule
    saving.run { [rules, dismiss] in
      try await rules.saveContentRule(draft)
      dismiss()
      return nil
    }
  }

  func test() {
    let draft = rule
    testing.run(retryable: true) { [rules] in try await rules.test(draft) }
  }
}

extension ContentRuleField {
  var localizedTitle: String {
    switch self {
      case .subject: String(localized: "Subject")
      case .body: String(localized: "Body")
      case .listID: String(localized: "List-ID")
      case .recipients: String(localized: "Recipients")
      case .replyTo: String(localized: "Reply-To")
      case .contentType: String(localized: "Content type")
      case .attachmentNames: String(localized: "Attachment names")
      case .attachmentTypes: String(localized: "Attachment types")
    }
  }
}
extension ContentRuleOperator {
  var localizedTitle: String {
    switch self {
      case .contains: String(localized: "Contains")
      case .equals: String(localized: "Equals")
      case .regularExpression: String(localized: "Regular expression")
    }
  }

  /// An expression of the kind this operator matches, shown in the empty field.
  fileprivate var examplePattern: String {
    switch self {
      case .contains, .equals: String(localized: "limited-time offer")
      case .regularExpression: #"free\s+gift"#
    }
  }
}

#Preview("Content rules") {
  let model = PreviewHelper.model()
  model.shared.state.contentRules = [PreviewHelper.contentRule]
  return ContentRulesPane(rules: model.rules, shared: model.shared).padding()
}
#Preview("No content rules") {
  let model = PreviewHelper.model()
  ContentRulesPane(rules: model.rules, shared: model.shared).padding()
}
#Preview("New content rule") {
  ContentRuleFormView(rules: PreviewHelper.model().rules, rule: ContentRule(), isNew: true)
}
