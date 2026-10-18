import SwiftUI

/// Explains that Mail Automation is off and opens its pane in System Settings.
struct AutomationDeniedView: View {
  /// Privacy & Security › Automation in System Settings.
  static let settingsURL = URL(
    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
  )
  @Environment(\.openURL) private var openURL

  var body: some View {
    Label {
      Text("SpamWise isn’t allowed to control Mail, so it can’t check or move mail.")
    } icon: {
      Image(systemName: "exclamationmark.triangle.fill").symbolRenderingMode(.multicolor)
        .accessibilityLabel("Warning")
    }
    Button("Open Automation Settings") {
      if let url = Self.settingsURL { openURL(url) }
    }
    .accessibilityIdentifier("mail.openAutomationSettings")
  }
}

#Preview("Automation denied") { Form { AutomationDeniedView() }.formStyle(.grouped) }
