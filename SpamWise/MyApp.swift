import AppIntents
import SwiftUI
import SpamWiseCore

@main struct SpamWiseApp: App {
  @State private var model: AppModel

  var body: some Scene {
    Window("SpamWise", id: "activity") {
      ContentView(model: model)
        .onOpenURL { model.handle($0) }
    }
    .defaultSize(width: 1060, height: 680)
    .defaultLaunchBehavior(.presented)
    .commands {
      ToolsCommands(model: model)
      CommandGroup(replacing: .help) {
        Button("SpamWise Help") { Help.open("getting-started") }
      }
    }
    SwiftUI.Settings { SettingsView(model: model) }
      .windowResizability(.contentSize)
    MenuBarExtra("SpamWise", systemImage: "envelope.badge.shield.half.filled") {
      MailMenuView(model: model)
    }
  }
  init() {
    let model = AppModel()
    AppDependencyManager.shared.add(dependency: model)
    SpamWiseShortcuts.updateAppShortcutParameters()
    _model = State(initialValue: model)
    model.startMonitoring()
  }

}
