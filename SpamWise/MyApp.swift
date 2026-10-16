import AppIntents
import SwiftUI
import SpamWiseCore

@main struct MyApp: App {
  @State private var model = AppModel()
  var body: some Scene {
    WindowGroup("SpamWise") {
      ContentView(model: model)
        .task { await model.monitor() }
        .onOpenURL { model.handle($0) }
    }
    .defaultSize(width: 1120, height: 720)
    .commands {
      CommandGroup(replacing: .help) { Button("SpamWise Help") { Help.open("getting-started") } }
    }
    SwiftUI.Settings { SettingsView(model: model) }
  }
}
@MainActor enum Help {
  static func open(_ page: String) {
    NSHelpManager.shared.openHelpAnchor(page, inBook: "codes.tim.SpamWise.help")
  }
}
struct HelpButton: View {
  var page: String
  var body: some View {
    Button {
      Help.open(page)
    } label: {
      Image(systemName: "questionmark.circle")
    }.buttonStyle(.plain).accessibilityLabel(
      "Help for \(Help.localizedTitle(for: page))"
    )
  }
}
