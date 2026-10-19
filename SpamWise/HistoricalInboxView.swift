import SwiftUI
import SpamWiseCore

struct HistoricalInboxView: View {
  let olderMail: OlderMailModel
  let shared: SharedStateModel
  let accountID: String
  @State private var page = 0

  var body: some View {
    if let start = olderMail.inboxStart(accountID: accountID) {
      let operation = olderMail.operation(for: accountID)
      LabeledContent("Automatic filtering starts", value: start.formatted())
      Stepper("Older mail page: \(page + 1)", value: $page, in: ScanCoordinator.previewPages)
      HStack {
        Group {
          Button("Preview older Inbox mail") {
            olderMail.preview(accountID: accountID, page: page)
          }
          Button("Apply previewed decisions") { olderMail.apply(accountID: accountID) }
            .disabled(olderMail.previews[accountID]?.isEmpty ?? true)
        }.disabled(shared.settings.dryRun)
        if operation.isBusy {
          ProgressView().controlSize(.small)
          Button("Stop") { operation.cancel() }
        }
      }
      OperationStatusView(operation: operation)
      Text(
        """
        Automatic checks read only mail received since filtering started. To sort older mail, turn \
        off dry run, preview a page, then apply it. Previews send messages to your provider, which \
        may cost money, and changing settings discards them.
        """
      )
      .foregroundStyle(.secondary)
    }
  }
}

#Preview("Not yet scanned") {
  let model = PreviewHelper.model()
  Form {
    HistoricalInboxView(olderMail: model.olderMail, shared: model.shared, accountID: "account")
  }
}
#Preview("Boundary recorded") {
  let model = PreviewHelper.model()
  var health = MailScanHealth(accountName: "Account")
  health.inboxStart = .now
  model.shared.scanHealth["account"] = health
  return Form {
    HistoricalInboxView(olderMail: model.olderMail, shared: model.shared, accountID: "account")
  }
}
