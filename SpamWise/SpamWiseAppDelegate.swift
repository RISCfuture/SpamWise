public import AppKit

/**
 Owns the app's single model and handles the launch and quit events SwiftUI doesn't expose.

 Each edition's `App` installs it with `@NSApplicationDelegateAdaptor` and builds its scenes
 from ``model``. When macOS opens SpamWise at login, or launches it for a Mail rule's
 `check-inbox` URL, the Activity window closes as soon as settings show setup is finished, so
 filtering continues from the menu bar. URLs and backup files reach ``AppModel`` here rather
 than through a window. Quitting waits for edits still waiting to be saved.
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
  /// Whether AppKit is still launching SpamWise, so URLs it opens now are why it launched.
  private var isLaunching = true

  /// Notes that launching is over, and a launch at login, which AppKit identifies only in the
  /// event it is handling now.
  public func applicationDidFinishLaunching(_: Notification) {
    isLaunching = false
    if Self.isHandlingLoginLaunch { model.router.closesWindowAtLaunch = true }
  }

  /**
   Handles `spamwise://` URLs and backups opened in Finder.

   A Mail rule's `check-inbox` URL checks mail without showing a window, closing the one
   macOS presents when the URL launched SpamWise; the other URLs and backups bring the
   Activity window forward.
   */
  public func application(_: NSApplication, open urls: [URL]) {
    if isLaunching, urls.allSatisfy(AppModel.isInboxCheck) {
      model.router.closesWindowAtLaunch = true
    }
    for url in urls { model.handle(url) }
  }

  /// Quits once settings and trust-exclusion edits that are still waiting to be saved are written.
  public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    Task {
      await model.savePendingEdits()
      sender.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }
}
