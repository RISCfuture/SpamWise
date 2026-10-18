import SwiftUI
import SpamWiseCore

struct ToolsCommands: Commands {
  let router: ActivityRouter
  let shared: SharedStateModel
  @Environment(\.openWindow) private var openWindow

  var body: some Commands {
    CommandMenu("Tools") {
      Button("Reviewed corpus") { show(.corpus) }
        .accessibilityIdentifier("activity.corpus")
        .keyboardShortcut("c", modifiers: [.command, .option])
        .disabled(!shared.settings.onboardingComplete)
      Button("Configuration history") { show(.audit) }
        .disabled(!shared.settings.onboardingComplete)
    }
  }

  private func show(_ sheet: ActivitySheet) {
    openWindow(id: "activity")
    router.present(sheet)
  }
}
