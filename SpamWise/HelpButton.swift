import SwiftUI

@MainActor enum Help {
  private static let bookNameKey = "CFBundleHelpBookName"

  /// The registered help book, as the app's Info.plist names it.
  private static var bookName: String? {
    Bundle.main.object(forInfoDictionaryKey: bookNameKey) as? String
  }

  static func open(_ page: String) {
    guard let bookName else { return }
    NSHelpManager.shared.openHelpAnchor(page, inBook: bookName)
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
