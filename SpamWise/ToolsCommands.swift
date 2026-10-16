import SwiftUI
import SpamWiseCore

struct ToolsCommands: Commands {
  let model: AppModel
  @Environment(\.openWindow) private var openWindow

  var body: some Commands {
    CommandMenu("Tools") {
      Button("Reviewed corpus") {
        openWindow(id: "activity"); model.showCorpus = true
      }.accessibilityIdentifier("activity.corpus")
        .keyboardShortcut("c", modifiers: [.command, .option])
        .disabled(!model.state.settings.onboardingComplete)
      Button("Configuration history") {
        openWindow(id: "activity"); model.showAudit = true
      }.disabled(!model.state.settings.onboardingComplete)
    }
  }
}
