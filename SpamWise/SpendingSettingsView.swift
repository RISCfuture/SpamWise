import SwiftUI
import SpamWiseCore

struct SpendingSettingsView: View {
  private static let defaultLimitUSD = 5.0
  let settings: SettingsModel
  let shared: SharedStateModel
  @State private var limitUSD = Self.defaultLimitUSD

  var body: some View {
    LabeledContent(
      "Month-to-date estimated API cost",
      value: shared.monthCost.formatted(.currency(code: "USD"))
    )
    .onChange(of: shared.spending?.limitUSD, initial: true) { _, saved in
      if let saved { limitUSD = saved }
    }
    if let spending = shared.spending {
      Toggle(
        "Limit monthly spending",
        isOn: Binding(
          get: { spending.limitMicroUSD != nil },
          set: { settings.setSpendingLimit(usd: $0 ? limitUSD : nil) }
        )
      )
      .accessibilityIdentifier("spending.limitEnabled")
      if spending.limitMicroUSD != nil {
        TextField(
          "Monthly limit",
          value: $limitUSD,
          format: .currency(code: "USD"),
          prompt: Text(Self.defaultLimitUSD, format: .currency(code: "USD"))
        )
        .accessibilityIdentifier("spending.limit")
        .onChange(of: limitUSD) { _, amount in
          if amount != spending.limitUSD { settings.setSpendingLimit(usd: amount) }
        }
        if let error = settings.spendingLimitError {
          Text(error).textSelection(.enabled).accessibilityIdentifier("spending.limitError")
        }
        LabeledContent(
          "Counted toward this month’s limit",
          value: spending.committedUSD.formatted(.currency(code: "USD"))
        )
        if shared.spendingLimitReached {
          Text(
            "This month’s limit has been reached. Paid classification resumes next month or when you raise the limit."
          )
          .accessibilityIdentifier("spending.limitReached")
        }
      }
    } else {
      Text("Spending information is unavailable. Shared storage could not be read.")
    }
  }
}

#Preview("Unlimited") { SpendingPreview(model: PreviewHelper.model()) }
#Preview("Limit reached") {
  SpendingPreview(model: PreviewHelper.model(spendingLimitReached: true))
}
#Preview("Invalid limit") {
  let model = PreviewHelper.model(spendingLimitReached: true)
  model.settings.spendingLimitError = OperationFailure.describe(SpendingLimitError.invalidAmount)
  return SpendingPreview(model: model)
}

/// Spending settings over preview models.
private struct SpendingPreview: View {
  let model: AppModel

  var body: some View {
    Form { Section { SpendingSettingsView(settings: model.settings, shared: model.shared) } }
      .formStyle(.grouped)
  }
}
