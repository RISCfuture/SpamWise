import SwiftUI
import SpamWiseCore

struct RuleFormView: View {
  @Environment(\.dismiss) private var dismiss
  let model: AppModel
  let rule: SenderRule?
  @State private var scope: RuleScope
  @State private var disposition: RuleDisposition
  @State private var value: String
  @State private var saveError: String?

  var body: some View {
    VStack(alignment: .leading) {
      Text(rule == nil ? "Add rule" : "Edit rule").font(.headline)
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
      }
      if let saveError { Text(saveError).textSelection(.enabled) }
      HStack {
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Spacer()
        Button("Save rule") {
          saveError = nil
          model.saveRule(scope: scope, value: value, disposition: disposition) { result in
            switch result {
              case .success: dismiss()
              case .failure(let error): saveError = AppModel.describe(error)
            }
          }
        }.keyboardShortcut(.defaultAction).accessibilityIdentifier("rules.save")
          .disabled((try? RuleManagement.normalized(value, scope: scope)) == nil || model.busy)
      }
    }.padding().frame(minWidth: 440, idealWidth: 500)
  }

  init(model: AppModel, rule: SenderRule? = nil) {
    self.model = model
    self.rule = rule
    _scope = State(initialValue: rule?.scope ?? .address)
    _disposition = State(initialValue: rule?.disposition ?? .allow)
    _value = State(initialValue: rule?.value ?? "")
  }
}

#Preview("Add rule") { RuleFormView(model: PreviewHelper.model()) }
#Preview("Edit rule") { RuleFormView(model: PreviewHelper.model(), rule: PreviewHelper.rule) }
