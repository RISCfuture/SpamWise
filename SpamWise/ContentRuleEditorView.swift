import SwiftUI
import SpamWiseCore
import UniformTypeIdentifiers

struct ContentRuleEditorView: View {
  let rules: RulesModel
  let shared: SharedStateModel
  @State private var selection: UUID?
  @State private var path: [ContentRuleRoute] = []
  @State private var importing = false
  @State private var exporting = false
  @State private var archive: RulesDocument?
  @State private var exportStatus: OperationStatus?
  @Environment(\.dismiss) private var dismiss

  private var contentRules: [ContentRule] {
    shared.state.contentRules.sorted { $0.updatedAt > $1.updatedAt }
  }

  var body: some View {
    NavigationStack(path: $path) {
      VStack(alignment: .leading) {
        Text("Address, then domain, then newest matching content rule, then trusted relationships.")
          .foregroundStyle(.secondary)
        ContentRuleTable(rules: contentRules, shared: shared, selection: $selection)
        HStack {
          Button("Add rule") { path.append(.add) }
          Button("Edit") {
            if let selection { path.append(.edit(selection)) }
          }
          .disabled(selection == nil)
          Button("Remove", role: .destructive) {
            if let selection { rules.removeContentRule(selection) }
          }.disabled(selection == nil)
          Menu("Transfer") {
            Button("Import content rules…") { importing = true }
            Button("Export content rules…") { exportRules() }.disabled(contentRules.isEmpty)
          }
          if rules.contentRules.isBusy { ProgressView().controlSize(.small) }
        }
        OperationStatusView(operation: rules.contentRules)
        StatusLabel(status: exportStatus)
      }
      .padding()
      .navigationTitle("Content rules")
      .toolbar { DoneToolbarItem(dismiss: dismiss, identifier: "contentRules.done") }
      .navigationDestination(for: ContentRuleRoute.self) { route in
        ContentRuleFormView(rules: rules, rule: rule(for: route), isNew: route == .add) {
          path.removeLast()
        }
      }
    }
    .frame(minWidth: 640, minHeight: 430)
    .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
      if case .success(let url) = result { rules.importContentRules(from: url) }
    }
    .fileExporter(
      isPresented: $exporting,
      document: archive,
      contentType: .json,
      defaultFilename: "SpamWise-content-rules"
    ) { exportStatus = ExportResult.status(of: $0, failure: "Rule export failed.") }
  }

  private func rule(for route: ContentRuleRoute) -> ContentRule {
    guard case .edit(let id) = route else { return ContentRule() }
    return shared.state.contentRules.first { $0.id == id } ?? ContentRule()
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

/// A content rule form pushed inside the content rules sheet.
private enum ContentRuleRoute: Hashable {
  case add
  case edit(UUID)
}

private struct ContentRuleTable: View {
  let rules: [ContentRule]
  let shared: SharedStateModel
  @Binding var selection: UUID?

  var body: some View {
    Table(rules, selection: $selection) {
      TableColumn("Field") { Text($0.field.localizedTitle) }
      TableColumn("Expression", value: \.pattern)
      TableColumn("Action") { Text($0.disposition.localizedTitle) }
      TableColumn("State") { Text($0.enabled ? "Enabled" : "Disabled") }
      TableColumn("Matches") { Text(shared.state.contentRuleHits[$0.id, default: 0].formatted()) }
      TableColumn("Skipped") {
        Text(shared.state.contentRuleSkips[$0.id, default: 0].formatted())
      }
    }
    .overlay {
      if rules.isEmpty {
        ContentUnavailableView(
          "No content rules",
          systemImage: "text.magnifyingglass",
          description: Text(
            "Add a rule to allow or block mail whose subject, body or headers match an expression."
          )
        )
      }
    }
  }
}

struct ContentRuleFormView: View {
  let rules: RulesModel
  @State var rule: ContentRule
  let isNew: Bool
  let close: () -> Void
  @State private var saving = TrackedOperation()
  @State private var testing = TrackedOperation()

  var body: some View {
    Form {
      Picker("Field", selection: $rule.field) {
        ForEach(ContentRuleField.allCases, id: \.self) { Text($0.localizedTitle).tag($0) }
      }
      Picker("Match", selection: $rule.operation) {
        ForEach(ContentRuleOperator.allCases, id: \.self) { Text($0.localizedTitle).tag($0) }
      }
      TextField("Expression", text: $rule.pattern)
      Picker("Action", selection: $rule.disposition) {
        Text("Allow").tag(RuleDisposition.allow)
        Text("Block").tag(RuleDisposition.block)
      }
      Toggle("Enabled", isOn: $rule.enabled)
      TextField("Notes", text: $rule.note, axis: .vertical)
      Text(
        "Expressions are case-insensitive and bounded. A timed-out rule leaves mail unchanged."
      )
      .foregroundStyle(.secondary)
      HStack {
        Button("Test selected Mail message") { test() }
        if testing.isBusy { ProgressView().controlSize(.small) }
      }
      OperationStatusView(operation: testing)
      OperationStatusView(operation: saving)
    }
    .formStyle(.grouped)
    .navigationTitle(isNew ? "Add content rule" : "Edit content rule")
    .navigationBarBackButtonHidden()
    .toolbar {
      ConfirmationToolbarItems(
        confirmTitle: "Save",
        canConfirm: (try? ContentRules.validate(rule)) != nil && !saving.isBusy,
        cancel: close,
        confirm: save
      )
    }
  }

  private func save() {
    let draft = rule
    saving.run { [rules, close] in
      try await rules.saveContentRule(draft)
      close()
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
}

#Preview("Content rules") {
  let model = PreviewHelper.model()
  ContentRuleEditorView(rules: model.rules, shared: model.shared)
}
#Preview("New content rule") {
  NavigationStack {
    ContentRuleFormView(rules: PreviewHelper.model().rules, rule: ContentRule(), isNew: true) {}
  }
}
