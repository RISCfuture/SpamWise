import SwiftUI
import SpamWiseCore

struct AccountSettingsView: View {
  @Bindable var model: AppModel

  var body: some View {
    Form {
      ModelSettingsView(model: model)
      IMAPSettingsView(model: model)
      if model.state.settings.advancedOptions.transport == .appleMail {
        MailConnectionView(model: model)
        MailRouteView(model: model)
      }
    }.formStyle(.grouped)
  }
}

#Preview("Apple Mail account") { AccountSettingsView(model: PreviewHelper.model()) }
#Preview("IMAP account") { AccountSettingsView(model: PreviewHelper.model(transport: .imap)) }
