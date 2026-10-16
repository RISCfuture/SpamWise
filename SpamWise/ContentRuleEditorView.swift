import SwiftUI
import SpamWiseCore
import MailIntegration

struct ContentRuleEditorView: View {
  let model: AppModel
  @State private var selection: UUID?
  @State private var editing: ContentRule?
  @State private var showsEditor = false
  @Environment(\.dismiss) private var dismiss

  private var rules: [ContentRule] {
    (model.state.contentRules ?? []).sorted { $0.updatedAt > $1.updatedAt }
  }
  var body: some View {
    VStack(alignment: .leading) {
      Text("Content rules").font(.title2)
      Text("Address, then domain, then newest matching content rule, then trusted relationships.")
        .foregroundStyle(.secondary)
      Table(rules, selection: $selection) {
        TableColumn("Field") { Text($0.field.localizedTitle) }
        TableColumn("Expression", value: \.pattern)
        TableColumn("Action") { Text($0.disposition.localizedTitle) }
        TableColumn("State") { Text($0.enabled ? "Enabled" : "Disabled") }
        TableColumn("Matches") { Text((model.state.contentRuleHits?[$0.id] ?? 0).formatted()) }
      }
      HStack {
        Button("Add rule") {
          editing = nil; showsEditor = true
        }
        Button("Edit") {
          editing = rules.first { $0.id == selection }; showsEditor = true
        }
        .disabled(selection == nil)
        Button("Remove", role: .destructive) { remove() }.disabled(selection == nil)
        Spacer()
        Button("Done") { dismiss() }
      }.disabled(model.busy)
    }.padding().frame(minWidth: 640, minHeight: 400)
      .sheet(isPresented: $showsEditor) {
        ContentRuleFormView(model: model, rule: editing ?? ContentRule())
      }
  }
  private func remove() {
    guard let selection else { return }
    model.run {
      guard let store = model.store else { throw IntegrationError.unavailable }
      try await ContentRuleManagement.remove(selection, store: store)
    }
  }
}

struct ContentRuleFormView: View {
  let model: AppModel
  @State var rule: ContentRule
  @State private var result = ""
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack {
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
        Button("Test selected Mail message") { preview() }.disabled(model.busy)
        if !result.isEmpty { Text(result).textSelection(.enabled) }
      }.formStyle(.grouped)
      HStack {
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Spacer()
        Button("Save") { save() }.keyboardShortcut(.defaultAction)
          .disabled((try? ContentRules.validate(rule)) == nil || model.busy)
      }.padding()
    }.frame(minWidth: 520, minHeight: 430)
  }
  private func save() {
    model.run {
      guard let store = model.store else { throw IntegrationError.unavailable }
      try await ContentRuleManagement.save(rule, store: store)
      dismiss()
    }
  }
  private func preview() {
    model.run {
      let envelope = try await model.adapter.selectedMessage()
      let message = try MIMEParser().parse(envelope.raw)
      var draft = rule; draft.updatedAt = .now
      let candidates = (model.state.contentRules ?? []).filter { $0.id != draft.id } + [draft]
      let matches = try ContentRules.matches(candidates, message: message)
      let senderRule = Gates.evaluate(
        address: message.fromAddress,
        domain: DomainResolver().domain(ofAddress: message.fromAddress),
        rules: model.state.rules,
        contact: nil,
        history: .init()
      )
      if senderRule != nil {
        result = String(localized: "An address or domain rule takes precedence.")
      } else if matches.first?.id == draft.id {
        result = String(localized: "This rule wins for the selected message.")
      } else {
        result = String(localized: "This rule does not win for the selected message.")
      }
    }
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

#Preview("Content rules") { ContentRuleEditorView(model: PreviewHelper.model()) }
#Preview("New content rule") {
  ContentRuleFormView(model: PreviewHelper.model(), rule: ContentRule())
}
