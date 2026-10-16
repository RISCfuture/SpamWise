import SwiftUI
import SpamWiseCore

struct MailMenuView: View {
  let model: AppModel
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Text(model.state.settings.paused ? "Filtering paused" : "SpamWise is running")
    Button("Show Activity") { openWindow(id: "activity") }
    Section("Selected messages in Mail") {
      Button("Mark as Good") {
        model.correctSelection(.inbox); openWindow(id: "activity")
      }
      .keyboardShortcut("g", modifiers: [.command, .option])
      Button("Mark as Junk") {
        model.correctSelection(.junk); openWindow(id: "activity")
      }
      .keyboardShortcut("j", modifiers: [.command, .option])
      Button("Mark for Review") {
        model.correctSelection(.review); openWindow(id: "activity")
      }
      .keyboardShortcut("r", modifiers: [.command, .option])
    }.disabled(model.busy || !model.storageReady)
    Button(model.state.settings.paused ? "Resume filtering" : "Pause filtering") {
      model.togglePause()
    }
    .disabled(!model.storageReady)
    SettingsLink()
    Divider()
    Button("Quit SpamWise") { NSApplication.shared.terminate(nil) }
  }
}

#Preview("Running") { MailMenuView(model: PreviewHelper.model()) }
#Preview("Paused") { MailMenuView(model: PreviewHelper.model(paused: true)) }
