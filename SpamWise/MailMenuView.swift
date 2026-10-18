import SwiftUI
import SpamWiseCore

/// The menu bar menu: status, selected-message corrections and Pause.
struct MailMenuView: View {
  let shared: SharedStateModel
  let scanning: ScanCoordinator
  let settings: SettingsModel
  let corrections: CorrectionsModel
  let router: ActivityRouter
  let storageReady: Bool
  @Environment(\.openWindow) private var openWindow

  /// Corrections and Pause wait for setup, whose window cannot show their results.
  private var canActOnMail: Bool { storageReady && shared.settings.onboardingComplete }

  var body: some View {
    Text(scanning.filteringStatus.localizedTitle)
    if scanning.progress != nil { Text("Checking mail…") }
    Button("Show Activity") { openWindow(id: "activity") }
    if let digest = shared.pendingDigest {
      Button("Review digest") { show(.digest) }
        .badge(digest.records.count)
    }
    Section("Selected messages in Mail") {
      Button("Mark as Good") { correctSelection(.inbox) }
        .keyboardShortcut("g", modifiers: [.command, .option])
      Button("Mark as Junk") { correctSelection(.junk) }
        .keyboardShortcut("j", modifiers: [.command, .option])
      Button("Mark for Review") { correctSelection(.review) }
        .keyboardShortcut("r", modifiers: [.command, .option])
    }.disabled(!canActOnMail)
    Button(shared.settings.paused ? "Resume filtering" : "Pause filtering") {
      settings.togglePause()
    }
    .disabled(!canActOnMail)
    SettingsLink()
    Divider()
    Button("Quit SpamWise") { NSApplication.shared.terminate(nil) }
  }

  private func correctSelection(_ label: MailLabel) {
    corrections.correctSelection(label)
    show(.selectionCorrections)
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
