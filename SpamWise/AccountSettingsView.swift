import SwiftUI
import SpamWiseCore

struct AccountSettingsView: View {
  let model: AppModel

  var body: some View {
    Form {
      IMAPSettingsView(
        settings: model.settings,
        imap: model.imap,
        storageReady: model.services.storageReady
      )
      if model.shared.settings.advancedOptions.transport == .appleMail {
        MailConnectionView(model: model)
      }
    }.formStyle(.grouped)
  }
}

#Preview("Apple Mail account") { AccountSettingsView(model: PreviewHelper.model()) }
#Preview("IMAP account") { AccountSettingsView(model: PreviewHelper.model(transport: .imap)) }
