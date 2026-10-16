import SwiftUI

@MainActor enum Help {
  static func open(_ page: String) {
    NSHelpManager.shared.openHelpAnchor(page, inBook: "codes.tim.SpamWise.help")
  }
}

struct HelpButton: NSViewRepresentable {
  let page: String

  func makeCoordinator() -> Coordinator { Coordinator(page: page) }

  func makeNSView(context: Context) -> NSButton {
    let button = NSButton(
      title: "",
      target: context.coordinator,
      action: #selector(Coordinator.showHelp)
    )
    button.bezelStyle = .helpButton
    button.setAccessibilityLabel(String(localized: "Help for \(Help.localizedTitle(for: page))"))
    return button
  }

  func updateNSView(_ button: NSButton, context: Context) {
    context.coordinator.page = page
    button.setAccessibilityLabel(String(localized: "Help for \(Help.localizedTitle(for: page))"))
  }

  func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSButton, context: Context) -> CGSize? {
    nsView.intrinsicContentSize
  }

  @MainActor final class Coordinator: NSObject {
    var page: String
    init(page: String) { self.page = page }
    @objc func showHelp() { Help.open(page) }
  }
}

#Preview("Help") { HelpButton(page: "getting-started") }
