import SwiftUI

/// A warning with the system's multicolor triangle, for problems the user should notice.
struct WarningLabel<Content: View>: View {
  @ViewBuilder let content: () -> Content

  var body: some View {
    Label {
      content()
    } icon: {
      Image(systemName: "exclamationmark.triangle.fill").symbolRenderingMode(.multicolor)
        .accessibilityLabel("Warning")
    }
  }
}

extension WarningLabel where Content == Text {
  /// A warning showing localized `text`.
  init(_ text: LocalizedStringKey) { self.init { Text(text) } }

  /// A warning showing `text` as given, such as an already localized failure.
  init(verbatim text: String) { self.init { Text(verbatim: text) } }
}

#Preview("Warning") {
  Form { WarningLabel("Mail didn’t respond in time.") }.formStyle(.grouped)
}
