import SwiftUI
import SpamWiseCore

/**
 The menu bar menu: status, selected-message corrections and Pause.

 Its items have no key equivalents, because a menu bar extra's shortcuts work only while its
 menu is open. The Correct Selected Mail shortcut action can be bound to a global key instead.
 */
struct MailMenuView: View {
  let shared: SharedStateModel
  let scanning: ScanCoordinator
  let settings: SettingsModel
  let corrections: CorrectionsModel
  let router: ActivityRouter
  let storageReady: Bool
  @Environment(\.openWindow)
  private var openWindow

  /// Corrections and Pause wait for setup, whose window cannot show their results.
  private var canActOnMail: Bool { storageReady && shared.settings.onboardingComplete }

  var body: some View {
    Text(scanning.filteringState.localizedTitle)
    if scanning.progress != nil { Text("Checking mail…") }
    Button("Show Activity") { openWindow(id: "activity") }
    if let digest = shared.pendingDigest {
      ActivityActionButton(action: .digest) { show(.digest) }
        .badge(digest.records.count)
    }
    SelectionCorrectionMenu(corrections: corrections, canActOnMail: canActOnMail, show: show)
    PauseFilteringButton(settings: settings, paused: shared.settings.paused)
      .disabled(!canActOnMail)
    SettingsLink()
    Divider()
    Button("Quit SpamWise") { NSApplication.shared.terminate(nil) }
  }

  private func show(_ sheet: ActivitySheet) {
    openWindow(id: "activity")
    router.present(sheet)
  }
}

#Preview("Running") {
  let model = PreviewHelper.model()
  MailMenuView(
    shared: model.shared,
    scanning: model.scanning,
    settings: model.settings,
    corrections: model.corrections,
    router: model.router,
    storageReady: true
  )
}
#Preview("Paused") {
  let model = PreviewHelper.model(paused: true)
  MailMenuView(
    shared: model.shared,
    scanning: model.scanning,
    settings: model.settings,
    corrections: model.corrections,
    router: model.router,
    storageReady: true
  )
}
