import SwiftUI

struct UpdateSettingsView: View {
  #if SPAMWISE_DIRECT_UPDATES && !APP_STORE
    @State private var updates = DirectUpdateModel()
  #endif

  var body: some View {
    Section("App updates") {
      #if APP_STORE
        Text("Updates are delivered through the Mac App Store.")
      #elseif SPAMWISE_DIRECT_UPDATES
        if updates.configuration != nil {
          Button("Check for updates") { Task { await updates.check() } }
            .disabled(!updates.canCheck)
            .accessibilityIdentifier("settings.checkForUpdates")
          if updates.isChecking { ProgressView("Checking for updates…") }
          if let status = updates.status { Text(status) }
          if updates.hasUpdate, let configuration = updates.configuration {
            Link("View release on GitHub", destination: configuration.releasesURL)
              .accessibilityIdentifier("settings.updateRelease")
          }
          Text(
            "Checks contact GitHub. Download and install updates yourself from the release page."
          )
          .foregroundStyle(.secondary)
        } else {
          Text("Direct update checks are not configured for this build.")
            .foregroundStyle(.secondary)
        }
      #else
        Text("Update checks are unavailable in this build.")
          .foregroundStyle(.secondary)
      #endif
    }
  }
}

#Preview("Updates") { Form { UpdateSettingsView() }.formStyle(.grouped) }
