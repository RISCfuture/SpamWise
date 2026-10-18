import AppIntents
import SpamWiseCommon
import SwiftUI

/**
 The Developer ID edition: notarized, published as a disk image on GitHub, and
 responsible for keeping itself current.

 It differs from the Mac App Store edition only in the update checker it
 injects, which adds the Check for Updates command and the update settings. The
 two editions build differently named modules and entry points so their
 symbols never collide in an index built from both.
 */
@main
struct SpamWiseDownloadApp: App {
  @State private var model: AppModel
  private let updates = GitHubUpdates()

  var body: some Scene {
    SpamWiseScenes(model: model, updates: updates)
  }

  init() {
    _model = State(initialValue: AppModel.launch())
    SpamWiseDownloadShortcuts.updateAppShortcutParameters()
    updates?.startAutomaticChecks()
  }
}
