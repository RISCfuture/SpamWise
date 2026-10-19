import AppIntents
import SpamWiseCommon
import SwiftUI

/**
 The Mac App Store edition. The store keeps it current, so it injects no update
 checker and shows no update controls.

 The two editions build differently named modules and entry points so their
 symbols never collide in an index built from both.
 */
@main
struct SpamWiseMASApp: App {
  @NSApplicationDelegateAdaptor private var delegate: SpamWiseAppDelegate

  var body: some Scene {
    SpamWiseScenes(model: delegate.model)
  }

  init() {
    SpamWiseMASShortcuts.updateAppShortcutParameters()
  }
}
