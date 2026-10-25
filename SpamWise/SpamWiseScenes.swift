public import SwiftUI
import SpamWiseCore

/**
 Every window, menu and menu bar item SpamWise presents, shared by both editions.

 Each edition's `App` passes the model its ``SpamWiseAppDelegate`` owns, and what
 differs between the editions: the downloadable edition supplies an
 ``UpdateChecking`` so its update command and settings appear, and the App Store
 edition, which the store keeps current, supplies none.
 */
public struct SpamWiseScenes: Scene {
  private let model: AppModel
  private let updates: (any UpdateChecking)?
  @AppStorage private var showsMenuBarItem: Bool
  @Environment(\.openWindow)
  private var openWindow

  public var body: some Scene {
    Window("SpamWise", id: "activity") {
      ContentView(model: model)
    }
    .defaultSize(width: 1060, height: 680)
    .defaultLaunchBehavior(.presented)
    .handlesExternalEvents(matching: [])
    .onChange(of: model.windowRequest, initial: true) { showRequestedWindow() }
    .commands {
      CommandGroup(replacing: .appInfo) { AboutButton() }
      if let updates {
        CommandGroup(after: .appInfo) { UpdateMenuButton(updates: updates) }
      }
      ActivityCommands(model: model)
      BackupCommands(router: model.router, shared: model.shared)
    }
    SwiftUI.Settings {
      SettingsView(model: model)
        .environment(\.updates, updates)
    }
    .windowResizability(.contentSize)
    MenuBarExtra(isInserted: $showsMenuBarItem) {
      MailMenuView(
        shared: model.shared,
        scanning: model.scanning,
        settings: model.settings,
        corrections: model.corrections,
        router: model.router,
        storageReady: model.services.storageReady,
        preferences: model.services.preferences
      )
    } label: {
      MenuBarLabel(scanning: model.scanning)
    }
  }

  /**
   Creates the scenes for a launched app.

   - Parameters:
     - model: The app’s single model, from ``SpamWiseAppDelegate/model``.
     - updates: The edition's update checker, or `nil` where the edition cannot
       update itself.
   */
  public init(model: AppModel, updates: (any UpdateChecking)? = nil) {
    self.model = model
    self.updates = updates
    _showsMenuBarItem = MenuBarLabel.isShown(in: model.services.preferences)
  }

  /// Shows Activity, and any sheet, when a URL, file, notification or the Dock asks for it.
  private func showRequestedWindow() {
    guard let request = model.takeWindowRequest() else { return }
    NSApplication.shared.activate()
    openWindow(id: "activity")
    if let sheet = request.sheet { model.router.present(sheet) }
  }
}
