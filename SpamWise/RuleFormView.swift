import SwiftUI
import SpamWiseCore

struct RuleFormView: View {
  @Environment(\.dismiss) private var dismiss
  let rules: RulesModel
  let rule: SenderRule?
  @State private var scope: RuleScope
  @State private var disposition: RuleDisposition
  @State private var value: String
  @State private var saving = TrackedOperation()

  private var isValid: Bool { (try? RuleManagement.normalized(value, scope: scope)) != nil }

  var body: some View {
    NavigationStack {
      Form {
        Picker("Rule scope", selection: $scope) {
          Text("Email address").tag(RuleScope.address)
          Text("Entire domain").tag(RuleScope.domain)
        }.disabled(rule != nil).accessibilityIdentifier("rules.scope")
        TextField("Address or registrable domain", text: $value)
          .disabled(rule != nil).accessibilityIdentifier("rules.value")
        Picker("Action", selection: $disposition) {
          Text("Allow").tag(RuleDisposition.allow).accessibilityIdentifier("rules.action.allow")
          Text("Block").tag(RuleDisposition.block).accessibilityIdentifier("rules.action.block")
        }.accessibilityIdentifier("rules.action")
        OperationStatusView(operation: saving, identifier: "rules.saveError")
      }
      .formStyle(.grouped)
      .navigationTitle(rule == nil ? "Add rule" : "Edit rule")
      .toolbar {
        ConfirmationToolbarItems(
          confirmTitle: "Save",
          confirmIdentifier: "rules.save",
          canConfirm: isValid && !saving.isBusy,
          cancel: { dismiss() },
          confirm: save
        )
      }
    }
    .frame(minWidth: 440, idealWidth: 500)
  }

  init(rules: RulesModel, rule: SenderRule? = nil) {
    self.rules = rules
    self.rule = rule
    _scope = State(initialValue: rule?.scope ?? .address)
    _disposition = State(initialValue: rule?.disposition ?? .allow)
    _value = State(initialValue: rule?.value ?? "")
  }

  private func save() {
    let scope = scope, value = value, disposition = disposition
    saving.run { [rules, dismiss] in
      try await rules.saveSenderRule(scope: scope, value: value, disposition: disposition)
      dismiss()
      return nil
    }
  }
}

#Preview("Add rule") { RuleFormView(rules: PreviewHelper.model().rules) }
#Preview("Edit rule") {
  RuleFormView(rules: PreviewHelper.model().rules, rule: PreviewHelper.rule)
}
