import AppKit
import SwiftUI

/**
 The menu bar item's template symbol and title, which follow the filtering state.

 The menu bar shows only the symbol; VoiceOver speaks the title, which names the state.
 */
struct MenuBarLabel: View {
  private static let preferenceKey = "menuBar.isShown"
  let scanning: ScanCoordinator

  var body: some View {
    let state = scanning.filteringState
    let title = String(localized: "SpamWise: \(state.localizedTitle)")
    Label {
      Text(title)
    } icon: {
      Image(nsImage: Self.symbol(state.menuBarSymbol, describedAs: title))
    }
  }

  /// The status item takes its accessibility name from the image, so the symbol carries the title.
  private static func symbol(_ name: String, describedAs title: String) -> NSImage {
    NSImage(systemSymbolName: name, accessibilityDescription: title) ?? NSImage()
  }

  /// Whether the menu bar item is shown, an interface preference of this Mac that starts on.
  static func isShown(in preferences: UserDefaults) -> AppStorage<Bool> {
    AppStorage(wrappedValue: true, preferenceKey, store: preferences)
  }
}

extension FilteringState {
  /// The SF Symbol the menu bar shows: a shield while filtering, an envelope while mail stays
  /// unchanged, a pause symbol while paused, and a warning when the state needs attention.
  fileprivate var menuBarSymbol: String {
    guard !needsAttention else { return "exclamationmark.triangle" }
    return switch self {
      case .filtering: "envelope.badge.shield.half.filled"
      case .paused: "pause.circle"
      default: "envelope"
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
