import AppIntents
import SpamWiseCommon

/// Brings the shared framework's App Intents into this edition's metadata.
struct SpamWiseMASIntentsPackage: AppIntentsPackage {
  static var includedPackages: [any AppIntentsPackage.Type] {
    [SpamWiseCommonIntentsPackage.self]
  }
}

/// The App Shortcuts macOS offers without setup, in Spotlight, Shortcuts and Siri.
struct SpamWiseMASShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: SpamWiseStatusIntent(),
      phrases: ["Check \(.applicationName) status"],
      shortTitle: "Filtering Status",
      systemImageName: "envelope.badge.shield.half.filled"
    )
  }
}
