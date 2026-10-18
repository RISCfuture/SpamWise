import SwiftUI
import SpamWiseCore

struct HistoricalInboxView: View {
  let model: AppModel
  let accountID: String
  @State private var page = 0

  var body: some View {
    if let start = model.inboxStart(accountID: accountID) {
      LabeledContent("Automatic filtering starts", value: start.formatted())
      Stepper("Older mail page: \(page + 1)", value: $page, in: 0...1000)
      HStack {
        Button("Preview older Inbox mail") {
          model.previewHistoricalInbox(accountID: accountID, page: page)
        }
        Button("Apply previewed decisions") { model.applyHistoricalPreview(accountID: accountID) }
          .disabled(model.historicalPreview[accountID]?.isEmpty ?? true)
      }.disabled(model.busy || model.state.settings.dryRun)
      Text("Automatic filtering reads only mail received after this date.")
        .foregroundStyle(.secondary)
      Text(
        """
        Previewing sends eligible older messages to your selected provider and may incur API \
        charges.
        """
      )
      .foregroundStyle(.secondary)
      Text(
        "Previewing and applying older mail require dry run off. Any settings change discards the preview."
      )
      .foregroundStyle(.secondary)
    }
  }
}

#Preview("Not yet scanned") {
  Form { HistoricalInboxView(model: PreviewHelper.model(), accountID: "account") }
}
#Preview("Boundary recorded") {
  let model = PreviewHelper.model()
  var health = MailScanHealth(accountName: "Account")
  health.inboxStart = .now
  model.scanHealth["account"] = health
  return Form { HistoricalInboxView(model: model, accountID: "account") }
}
