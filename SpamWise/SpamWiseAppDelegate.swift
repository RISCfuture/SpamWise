public import AppKit

/**
 Owns the app's single model and handles the launch and quit events SwiftUI doesn't expose.

 Each edition's `App` installs it with `@NSApplicationDelegateAdaptor` and builds its scenes
 from ``model``. When macOS opens SpamWise at login, the Activity window closes as soon as
 settings show setup is finished, so filtering continues from the menu bar. Quitting waits
 for settings edits still waiting to be saved.
 */
@MainActor
public final class SpamWiseAppDelegate: NSObject, NSApplicationDelegate {
  /// Whether the Apple event AppKit is handling opened SpamWise as a login item.
  private static var isHandlingLoginLaunch: Bool {
    guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
    return event.eventID == kAEOpenApplication
      && event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue
        == keyAELaunchedAsLogInItem
  }
  /// The model every scene, menu and App Intent shares.
  public let model = AppModel.launch()

  /// Notes a launch at login, which AppKit identifies only in the event it is handling now.
  public func applicationDidFinishLaunching(_: Notification) {
    if Self.isHandlingLoginLaunch { model.router.closesWindowAtLogin = true }
  }

  /// Quits once settings edits that are still waiting to be saved are written.
  public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    Task {
      await model.settings.savePendingEdits()
      sender.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }
}
