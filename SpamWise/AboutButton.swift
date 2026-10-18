import AppKit
import SwiftUI

/// The app menu's About item: the standard About panel, carrying SpamWise's third-party notices.
struct AboutButton: View {
  var body: some View {
    Button("About SpamWise") {
      NSApplication.shared.orderFrontStandardAboutPanel(options: [.credits: Credits.text])
      NSApplication.shared.activate()
    }
  }
}

/// The notices the bundled open-source components require, as the About panel shows them.
private enum Credits {
  static var text: NSAttributedString {
    let source = String(
      localized: """
        SpamWise includes the open-source software below. The complete notices are in CREDITS.md \
        in the [SpamWise repository](https://github.com/RISCfuture/SpamWise).

        **ClaudeForFoundationModels** (revision 0262e1a). Copyright 2026 Anthropic PBC. Licensed \
        under the Apache License, Version 2.0.

        **swift-log**. Copyright 2018–2019 The SwiftLog Project. Licensed under the Apache \
        License, Version 2.0. Contains a derivation of the lock implementation from SwiftNIO.

        **SwiftNIO** and **swift-nio-imap**. Copyright Apple Inc. and the SwiftNIO project \
        authors. Licensed under the Apache License, Version 2.0.

        **Public Suffix List**. Licensed under the Mozilla Public License, Version 2.0. Source: \
        [publicsuffix.org](https://publicsuffix.org/list/).

        The downloadable edition also includes **GitHubUpdateChecker**, **swift-markdown-ui** and \
        **NetworkImage**, licensed under the MIT License, and **swift-cmark**, licensed under the \
        BSD 2-Clause License.

        The Apache License, Version 2.0 is available at \
        [apache.org](https://www.apache.org/licenses/LICENSE-2.0).

        SpamWise is not affiliated with, endorsed by, or sponsored by Anthropic. Claude is a \
        trademark of Anthropic PBC.
        """
    )
    let markdown =
      (try? AttributedString(
        markdown: source,
        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
      )) ?? AttributedString(source)
    let text = NSMutableAttributedString(markdown)
    for run in markdown.runs {
      let isBold = run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true
      text.addAttribute(.font, value: font(bold: isBold), range: NSRange(run.range, in: markdown))
    }
    text.addAttribute(
      .foregroundColor,
      value: NSColor.labelColor,
      range: NSRange(location: 0, length: text.length)
    )
    return text
  }

  private static func font(bold: Bool) -> NSFont {
    let size = NSFont.smallSystemFontSize
    return bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
  }
}
