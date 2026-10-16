import AppKit
import SwiftUI

/**
 The app menu's About item: the standard About panel, carrying SpamWise's third-party notices.

 The panel summarizes the bundled open-source components, then reproduces their NOTICE files and
 license texts, which ship inside the app. The downloadable edition bundles the notices of the
 extra components it links, so the panel lists those only where they are present.
 */
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
  private static let paragraphBreak = "\n\n"

  static var text: NSAttributedString {
    let editionNotices = NoticeFile.edition.contents
    let text = NSMutableAttributedString()
    for paragraph in summary(includesEditionComponents: editionNotices != nil) {
      text.append(styled(paragraph))
      text.append(plain(paragraphBreak))
    }
    for notices in [NoticeFile.shared.contents, editionNotices].compactMap(\.self) {
      text.append(plain(paragraphBreak))
      text.append(monospaced(notices))
    }
    text.addAttribute(
      .foregroundColor,
      value: NSColor.labelColor,
      range: NSRange(location: 0, length: text.length)
    )
    return text
  }

  private static func summary(includesEditionComponents: Bool) -> [String] {
    let shared = String(
      localized: """
        SpamWise includes the open-source software below. Their notices and licenses follow.

        **ClaudeForFoundationModels** (revision 0262e1a). Copyright 2026 Anthropic PBC. Licensed \
        under the Apache License, Version 2.0.

        **SwiftNIO**, **swift-nio-imap**, **swift-nio-transport-services**, **swift-collections**, \
        **swift-atomics**, **swift-system** and **swift-se0270-range-set**. Copyright Apple Inc. \
        and the Swift and SwiftNIO project authors. Licensed under the Apache License, Version 2.0.

        **Public Suffix List**. Licensed under the Mozilla Public License, Version 2.0. Source: \
        [publicsuffix.org](https://publicsuffix.org/list/).
        """
    )
    let edition = String(
      localized: """
        This edition also includes **swift-log**, licensed under the Apache License, Version 2.0; \
        **GitHubUpdateChecker**, **swift-markdown-ui** and **NetworkImage**, licensed under the \
        MIT License; and **swift-cmark**, licensed under the BSD 2-Clause License.
        """
    )
    let disclaimer = String(
      localized: """
        SpamWise is not affiliated with, endorsed by, or sponsored by Anthropic. Claude is a \
        trademark of Anthropic PBC.
        """
    )
    return includesEditionComponents ? [shared, edition, disclaimer] : [shared, disclaimer]
  }

  /// `markdown` with bold runs and links, in the panel's small system font.
  private static func styled(_ markdown: String) -> NSAttributedString {
    let parsed =
      (try? AttributedString(
        markdown: markdown,
        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
      )) ?? AttributedString(markdown)
    let text = NSMutableAttributedString(parsed)
    for run in parsed.runs {
      let isBold = run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true
      text.addAttribute(.font, value: font(bold: isBold), range: NSRange(run.range, in: parsed))
    }
    return text
  }

  private static func plain(_ string: String) -> NSAttributedString {
    NSAttributedString(string: string, attributes: [.font: font(bold: false)])
  }

  private static func monospaced(_ string: String) -> NSAttributedString {
    NSAttributedString(
      string: string,
      attributes: [
        .font: NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
      ]
    )
  }

  private static func font(bold: Bool) -> NSFont {
    let size = NSFont.smallSystemFontSize
    return bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
  }
}

/// A bundled file of verbatim NOTICE and license texts, kept in English as their authors wrote them.
private enum NoticeFile {
  /// The components both editions link, bundled with the shared interface.
  case shared
  /// The downloadable edition's update checker and its dependencies, bundled with that edition.
  case edition

  private static let fileExtension = "txt"

  /// The file's text, or nil when this edition doesn't bundle it.
  var contents: String? {
    guard let url = bundle.url(forResource: name, withExtension: Self.fileExtension) else {
      assert(self == .edition, "SpamWise is missing \(name).\(Self.fileExtension).")
      return nil
    }
    return try? String(contentsOf: url, encoding: .utf8)
  }

  private var name: String {
    switch self {
      case .shared: "ThirdPartyNotices"
      case .edition: "DownloadThirdPartyNotices"
    }
  }

  private var bundle: Bundle {
    switch self {
      case .shared: #bundle
      case .edition: .main
    }
  }
}
