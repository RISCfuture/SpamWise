import AppIntents

struct SpamWiseShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: SpamWiseStatusIntent(),
      phrases: ["Check \(.applicationName) status"],
      shortTitle: "Filtering Status",
      systemImageName: "envelope.badge.shield.half.filled"
    )
  }
}
