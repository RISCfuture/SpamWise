import AppIntents
import SwiftUI
import SpamWiseCore

@main struct SpamWiseApp: App {
  @State private var model = AppModel()

  var body: some Scene {
    WindowGroup("SpamWise") {
      ContentView(model: model)
        .task { await model.monitor() }
        .onOpenURL { model.handle($0) }
    }
    .defaultSize(width: 1060, height: 680)
    .commands {
      CommandGroup(replacing: .help) {
        Button("SpamWise Help") { Help.open("getting-started") }
      }
    }
    SwiftUI.Settings { SettingsView(model: model) }
      .windowResizability(.contentSize)
  }
}
