import SwiftUI

/// The menu bar item's template symbol and spoken label, which follow the filtering state.
struct MenuBarLabel: View {
  /// The interface preference that records whether the menu bar item is shown.
  static let preferenceKey = "menuBar.isShown"
  let scanning: ScanCoordinator

  var body: some View {
    let state = scanning.filteringState
    Label("SpamWise", systemImage: state.menuBarSymbol)
      .accessibilityLabel(Text("SpamWise: \(state.localizedTitle)"))
  }
}

extension FilteringState {
  /// The SF Symbol the menu bar shows: a shield while filtering, an envelope while mail stays
  /// unchanged, a pause symbol while paused, and a warning when the state needs attention.
  fileprivate var menuBarSymbol: String {
    switch self {
      case .filtering: "envelope.badge.shield.half.filled"
      case .paused: "pause.circle"
      case .setupIncomplete, .mailNotRunning, .rolesNotValidated, .dryRun: "envelope"
      case .mailNotAuthorized, .offline, .failing: "exclamationmark.triangle"
    }
  }
}

#Preview("Menu bar item") {
  MenuBarLabel(scanning: PreviewHelper.model().scanning).padding()
}
#Preview("Menu bar item, paused") {
  MenuBarLabel(scanning: PreviewHelper.model(paused: true).scanning).padding()
}
#Preview("Menu bar item, setup unfinished") {
  MenuBarLabel(scanning: PreviewHelper.model(onboarding: true).scanning).padding()
}
