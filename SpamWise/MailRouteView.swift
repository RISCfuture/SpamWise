import SwiftUI
import SpamWiseCore

struct MailRouteView: View {
  let model: AppModel

  private var route: Binding<IncomingRoute> {
    Binding(
      get: { model.state.settings.incomingRoute },
      set: { value in model.setSetting(\.route, to: value) }
    )
  }

  var body: some View {
    Section("Incoming mail") {
      Picker("Incoming route", selection: route) {
        ForEach([IncomingRoute.mailRule, .mailKit], id: \.self) { route in
          Text(route.localizedTitle).tag(route)
        }
      }
      .accessibilityIdentifier("mail.route")
      .disabled(!model.storageReady)
      Text(
        """
        The Mail extension can’t tell which account a message belongs to, so it can’t filter by \
        account. It previews decisions only when all accounts are included, and it never moves mail.
        """
      )
      .foregroundStyle(.secondary)
      if model.state.settings.incomingRoute == .mailKit {
        Text(
          """
          Enable SpamWise in Mail → Settings → Extensions. Automatic Inbox checks stay off while \
          the extension previews incoming mail.
          """
        )
        if model.state.settings.mailOptions.accountIDs != nil {
          Text(
            """
            Only some accounts are included, so the extension previews nothing and no mail is \
            checked. Include all accounts or choose Automation checks.
            """
          )
        }
      }
    }
  }
}

#Preview("Automation checks") {
  Form { MailRouteView(model: PreviewHelper.model()) }.formStyle(.grouped)
}
#Preview("Mail extension preview") {
  let model = PreviewHelper.model()
  model.state.settings.route = .mailKit
  return Form { MailRouteView(model: model) }.formStyle(.grouped)
}
