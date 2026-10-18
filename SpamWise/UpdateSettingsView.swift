import SwiftUI

struct UpdateSettingsView: View {
  @Environment(\.updates) private var updates

  var body: some View {
    if let updates {
      UpdateControls(updates: updates)
    }
  }
}

private struct UpdateControls: View {
  let updates: any UpdateChecking

  var body: some View {
    Section("App updates") {
      Picker("Check for updates", selection: cadence) {
        ForEach(UpdateCheckCadence.allCases) { choice in
          Text(choice.localizedTitle).tag(choice)
        }
      }
      .accessibilityIdentifier("settings.updateCadence")
      Toggle("Include prerelease versions", isOn: includesPrereleases)
        .accessibilityIdentifier("settings.updatePrereleases")
      LabeledContent("Last checked") {
        LastCheckedLabel(date: updates.lastCheckDate)
      }
      HStack {
        Button("Check Now") { Task { await updates.checkForUpdatesAndShowUI() } }
          .disabled(!updates.canCheckForUpdates)
          .accessibilityIdentifier("settings.checkForUpdates")
        Spacer(minLength: 0)
        Button("Reset Skipped Versions") { updates.resetSkippedVersions() }
          .disabled(!updates.hasSkippedVersions)
          .accessibilityIdentifier("settings.resetSkippedVersions")
      }
    }
  }

  private var cadence: Binding<UpdateCheckCadence> {
    Binding {
      updates.cadence
    } set: {
      updates.cadence = $0
    }
  }

  private var includesPrereleases: Binding<Bool> {
    Binding {
      updates.includesPrereleases
    } set: {
      updates.includesPrereleases = $0
    }
  }
}

private struct LastCheckedLabel: View {
  let date: Date?

  var body: some View {
    Group {
      if let date {
        Text(date, format: .relative(presentation: .named))
      } else {
        Text("Never")
      }
    }
    .foregroundStyle(.secondary)
  }
}

/// Starts a check from the app menu; the checker presents its own result window.
struct UpdateMenuButton: View {
  let updates: any UpdateChecking

  var body: some View {
    Button("Check for Updates…") { Task { await updates.checkForUpdatesAndShowUI() } }
      .disabled(!updates.canCheckForUpdates)
  }
}

#if DEBUG
  @MainActor @Observable private final class PreviewUpdateChecker: UpdateChecking {
    var canCheckForUpdates = true
    var lastCheckDate: Date?
    var cadence = UpdateCheckCadence.daily
    var includesPrereleases = false
    var hasSkippedVersions: Bool

    init(lastCheckDate: Date? = nil, hasSkippedVersions: Bool = false) {
      self.lastCheckDate = lastCheckDate
      self.hasSkippedVersions = hasSkippedVersions
    }

    func checkForUpdatesAndShowUI() async {}

    func resetSkippedVersions() { hasSkippedVersions = false }
  }

  #Preview("Updates — checked") {
    Form { UpdateSettingsView() }.formStyle(.grouped)
      .environment(
        \.updates,
        PreviewUpdateChecker(
          lastCheckDate: .now.addingTimeInterval(-3600),
          hasSkippedVersions: true
        )
      )
  }

  #Preview("Updates — never checked") {
    Form { UpdateSettingsView() }.formStyle(.grouped)
      .environment(\.updates, PreviewUpdateChecker())
  }

  #Preview("Updates — App Store edition") {
    Form { UpdateSettingsView() }.formStyle(.grouped)
  }
#endif
