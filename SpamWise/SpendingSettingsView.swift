import SwiftUI
import SpamWiseCore

struct SpendingSettingsView: View {
  private static let defaultLimitUSD = 5.0
  let model: AppModel
  @State private var limitUSD = Self.defaultLimitUSD

  var body: some View {
    LabeledContent(
      "Month-to-date estimated API cost",
      value: model.monthCost.formatted(.currency(code: "USD"))
    )
    if let spending = model.spending {
      Toggle(
        "Limit monthly spending",
        isOn: Binding(
          get: { spending.limitMicroUSD != nil },
          set: { model.setSpendingLimit(usd: $0 ? limitUSD : nil) }
        )
      )
      .accessibilityIdentifier("spending.limitEnabled")
      if spending.limitMicroUSD != nil {
        TextField("Monthly limit", value: $limitUSD, format: .currency(code: "USD"))
          .accessibilityIdentifier("spending.limit")
          .onChange(of: limitUSD) { _, amount in
            if amount != spending.limitUSD { model.setSpendingLimit(usd: amount) }
          }
        if let error = model.spendingLimitError {
          Text(error).textSelection(.enabled).accessibilityIdentifier("spending.limitError")
        }
        LabeledContent(
          "Counted toward this month’s limit",
          value: spending.committedUSD.formatted(.currency(code: "USD"))
        )
        if model.spendingLimitReached {
          Text(
            "This month’s limit has been reached. Paid classification resumes next month or when you raise the limit."
          )
          .accessibilityIdentifier("spending.limitReached")
        }
      }
    } else {
      Text("Spending information is unavailable. Shared storage could not be read.")
    }
    HStack(alignment: .top) {
      Text(
        """
        Each paid request counts its largest possible cost until it finishes, then its measured \
        cost. The limit starts over each calendar month.
        """
      )
      .foregroundStyle(.secondary)
      Spacer()
      HelpButton(page: "what-data-is-sent")
    }
    .onChange(of: model.spending?.limitUSD, initial: true) { _, saved in
      if let saved { limitUSD = saved }
    }
  }
}

#Preview("Unlimited") {
  Form { SpendingSettingsView(model: PreviewHelper.model()) }.formStyle(.grouped)
}
#Preview("Limit reached") {
  Form { SpendingSettingsView(model: PreviewHelper.model(spendingLimitReached: true)) }
    .formStyle(.grouped)
}
#Preview("Invalid limit") {
  let model = PreviewHelper.model(spendingLimitReached: true)
  model.spendingLimitError = AppModel.describe(SpendingLimitError.invalidAmount)
  return Form { SpendingSettingsView(model: model) }.formStyle(.grouped)
}
