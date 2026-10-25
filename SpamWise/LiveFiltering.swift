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

/// The next step out of dry run: starting live filtering, or first the connection check it needs.
struct LeaveDryRunButton: View {
  let state: FilteringState
  /// The mail integration whose connection check finds the mailboxes.
  let transport: MailTransport
  /// Whether the Activity window can ask to confirm live filtering, which it can't over a sheet.
  let canStartFiltering: Bool
  /// Asks to confirm live filtering.
  let startFiltering: () -> Void
  /// Shows the check that finds each account’s Inbox and Junk.
  let checkConnection: () -> Void

  var body: some View {
    switch state {
      case .dryRun:
        Button("Start Filtering…", action: startFiltering)
          .disabled(!canStartFiltering)
          .help("Turns off dry run so SpamWise moves Junk and marks Review messages.")
          .accessibilityIdentifier("activity.startFiltering")
      case .rolesNotValidated:
        CheckConnectionButton(transport: transport, action: checkConnection)
      default:
        EmptyView()
    }
  }
}

/// Opens the connection check, named as the transport's Settings button is.
private struct CheckConnectionButton: View {
  let transport: MailTransport
  let action: () -> Void

  var body: some View {
    Group {
      switch transport {
        case .appleMail: Button("Check Mail Connection…", action: action)
        case .imap: Button("Check Connection…", action: action)
      }
    }
    .help("SpamWise needs each account’s Inbox and Junk before it can start filtering.")
    .accessibilityIdentifier("activity.checkMailConnection")
  }
}

/// Brings SpamWise forward with Settings open on General, where the connection check is.
@MainActor
func showConnectionCheck(preferences: UserDefaults, openSettings: OpenSettingsAction) {
  SettingsPane.general.select(in: preferences)
  NSApplication.shared.activate()
  openSettings()
}

#Preview("Leaving dry run") {
  VStack(alignment: .leading) {
    LeaveDryRunButton(state: .dryRun, transport: .appleMail, canStartFiltering: true) {
    } checkConnection: {
    }
    LeaveDryRunButton(state: .rolesNotValidated, transport: .appleMail, canStartFiltering: true) {
    } checkConnection: {
    }
    LeaveDryRunButton(state: .rolesNotValidated, transport: .imap, canStartFiltering: true) {
    } checkConnection: {
    }
  }.padding()
}
