public import SwiftUI
import AppIntents
import SpamWiseCore

/**
 Every window, menu and menu bar item SpamWise presents, shared by both editions.

 Each edition's `App` creates the model once with ``AppModel/launch()`` and passes
 what differs between them: the downloadable edition supplies an
 ``UpdateChecking`` so its update command and settings appear, and the App Store
 edition, which the store keeps current, supplies none.
 */
public struct SpamWiseScenes: Scene {
  private let model: AppModel
  private let updates: (any UpdateChecking)?

  public var body: some Scene {
    Window("SpamWise", id: "activity") {
      ContentView(model: model)
        .onOpenURL { model.handle($0) }
    }
    .defaultSize(width: 1060, height: 680)
    .defaultLaunchBehavior(.presented)
    .commands {
      CommandGroup(replacing: .appInfo) { AboutButton() }
      if let updates {
        CommandGroup(after: .appInfo) { UpdateMenuButton(updates: updates) }
      }
      ToolsCommands(model: model)
      CommandGroup(replacing: .help) {
        Button("SpamWise Help") { Help.open("getting-started") }
      }
    }
    SwiftUI.Settings {
      SettingsView(model: model)
        .environment(\.updates, updates)
    }
    .windowResizability(.contentSize)
    MenuBarExtra("SpamWise", systemImage: "envelope.badge.shield.half.filled") {
      MailMenuView(model: model)
    }
  }

  /**
   Creates the scenes for a launched app.

   - Parameters:
     - model: The app's single model, from ``AppModel/launch()``.
     - updates: The edition's update checker, or `nil` where the edition cannot
       update itself.
   */
  public init(model: AppModel, updates: (any UpdateChecking)? = nil) {
    self.model = model
    self.updates = updates
  }
}

extension AppModel {
  /**
   Creates the model a launched app runs on, makes it available to App Intents
   and starts monitoring Mail.

   Call this once, from the edition's `App` initializer.
   */
  public static func launch() -> AppModel {
    let model = AppModel()
    unsafe AppDependencyManager.shared.add(dependency: model)
    model.startMonitoring()
    return model
  }
}
