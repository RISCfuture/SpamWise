import SwiftUI
import SpamWiseCore

/// Asks before dry run ends, saying what live filtering does to mail.
private struct LiveFilteringConfirmation: ViewModifier {
  @Binding var isPresented: Bool
  let settings: SettingsModel

  func body(content: Content) -> some View {
    content.confirmationDialog(
      "Turn off dry run?",
      isPresented: $isPresented,
      titleVisibility: .visible
    ) {
      Button("Turn Off Dry Run") { settings.setSetting(\.dryRun, to: false) }
        .accessibilityIdentifier("settings.dryRun.confirm")
      Button("Cancel", role: .cancel) {}
        .accessibilityIdentifier("settings.dryRun.cancel")
    } message: {
      Text(
        """
        SpamWise will move new Junk to each checked account’s Junk mailbox and mark Review \
        messages in Inbox. It checks every move afterward. If Mail doesn’t confirm a move, \
        SpamWise doesn’t retry or reverse it, and Activity shows the failure so you can check the \
        message in Mail.
        """
      )
    }
  }
}

extension View {
  /// Confirms ending dry run before `settings` turns it off.
  func liveFilteringConfirmation(isPresented: Binding<Bool>, settings: SettingsModel) -> some View {
    modifier(LiveFilteringConfirmation(isPresented: isPresented, settings: settings))
  }
}

/// The next step out of dry run: starting live filtering, or first the Mail connection check it needs.
struct LeaveDryRunButton: View {
  let state: FilteringState
  /// Asks to confirm live filtering.
  let startFiltering: () -> Void
  /// Shows the check that finds each account’s Inbox and Junk.
  let checkConnection: () -> Void

  var body: some View {
    switch state {
      case .dryRun:
        Button("Start Filtering…", action: startFiltering)
          .help("Turns off dry run so SpamWise moves Junk and marks Review messages.")
          .accessibilityIdentifier("activity.startFiltering")
      case .rolesNotValidated:
        Button("Check Mail Connection…", action: checkConnection)
          .help("SpamWise needs each account’s Inbox and Junk before it can start filtering.")
          .accessibilityIdentifier("activity.checkMailConnection")
      default:
        EmptyView()
    }
  }
}

/// Brings SpamWise forward with Settings open on General, where the Mail connection check is.
@MainActor
func showConnectionCheck(preferences: UserDefaults, openSettings: OpenSettingsAction) {
  SettingsPane.general.select(in: preferences)
  NSApplication.shared.activate()
  openSettings()
}

#Preview("Leaving dry run") {
  VStack(alignment: .leading) {
    LeaveDryRunButton(state: .dryRun) {
    } checkConnection: {
    }
    LeaveDryRunButton(state: .rolesNotValidated) {
    } checkConnection: {
    }
  }.padding()
}
