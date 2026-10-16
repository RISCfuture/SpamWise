import Foundation
import MessageModel

/**
 A message body split into new text and text quoted from earlier mail.

 The sender controls the body, so quoted text is separated only for a genuine reply: one that
 carries In-Reply-To or References, or whose quotation follows new text. Separated text is never
 discarded outright; ``fitted(to:)`` keeps a minimum share of it and counts what it leaves out.
 */
struct QuotedReply {
  private static let minimumQuotedShareDivisor = 4
  private static let originalMessageMarker = "-----Original Message-----"
  private static let alternativeMarkerPrefix = "[Alternative "
  /// New text written for this message.
  let text: String
  /// Quoted lines, attributions and forwarded originals, in message order.
  let quoted: String

  init(_ message: ParsedMessage) {
    self.init(
      text: message.text,
      isReply: message.header("in-reply-to") != nil || message.header("references") != nil
    )
  }

  init(text: String, isReply: Bool) {
    let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
    let kinds = Self.kinds(of: lines)
    guard isReply || Self.quotationFollowsNewText(lines: lines, kinds: kinds) else {
      self.text = text; quoted = ""
      return
    }
    self.text = zip(lines, kinds).filter { $0.1 == .new }.map(\.0).joined(separator: "\n")
    quoted = zip(lines, kinds).filter { $0.1 == .quoted }.map(\.0).joined(separator: "\n")
  }

  private static func kinds(of lines: [Substring]) -> [LineKind] {
    var insideOriginal = false
    return lines.map { line in
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix(originalMessageMarker) { insideOriginal = true }
      let isQuoted =
        insideOriginal || trimmed.hasPrefix(">")
        || (line.hasPrefix("On ") && trimmed.hasSuffix("wrote:"))
      return isQuoted ? .quoted : .new
    }
  }

  private static func quotationFollowsNewText(lines: [Substring], kinds: [LineKind]) -> Bool {
    guard let firstQuoted = kinds.firstIndex(of: .quoted) else { return false }
    return lines[..<firstQuoted].contains { !$0.allSatisfy(\.isWhitespace) }
  }

  /**
   Shortens `text` to `limit` characters, sharing the room among its MIME alternatives.

   Each `[Alternative N]` section receives an equal share, and room a shorter section leaves
   goes to the longer ones, so one long alternative cannot crowd out the rest.
   */
  static func shortened(_ text: String, to limit: Int) -> String {
    guard text.count > limit else { return text }
    let sections = alternativeSections(of: text)
    guard sections.count > 2 else { return String(text.prefix(limit)) }
    let lead = sections[0], alternatives = Array(sections.dropFirst())
    let separators = sections.count - 1
    var remaining = max(0, limit - lead.count - separators)
    var allowance = Array(repeating: 0, count: alternatives.count)
    for (position, index) in alternatives.indices.sorted(by: {
      alternatives[$0].count < alternatives[$1].count
    }).enumerated() {
      allowance[index] = min(alternatives[index].count, remaining / (alternatives.count - position))
      remaining -= allowance[index]
    }
    let shared = zip(alternatives, allowance).map { String($0.prefix($1)) }
    return String(([String(lead)] + shared).joined(separator: "\n").prefix(limit))
  }

  /// The text before the first alternative marker, then each marked alternative with its marker.
  private static func alternativeSections(of text: String) -> [Substring] {
    let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
    var sections: [[Substring]] = [[]]
    for line in lines {
      if isAlternativeMarker(line) { sections.append([]) }
      sections[sections.count - 1].append(line)
    }
    return sections.map { Substring($0.joined(separator: "\n")) }
  }

  private static func isAlternativeMarker(_ line: Substring) -> Bool {
    guard line.hasPrefix(alternativeMarkerPrefix), line.hasSuffix("]") else { return false }
    let number = line.dropFirst(alternativeMarkerPrefix.count).dropLast()
    return !number.isEmpty && number.allSatisfy { $0.isASCII && $0.isNumber }
  }

  /**
   Fits new and quoted text into `limit` characters.

   Quoted text receives at least a quarter of the limit, or all the room new text leaves, so a
   sender cannot hide the body by presenting it as a quotation.
   */
  func fitted(to limit: Int) -> Body {
    guard !quoted.isEmpty else {
      return Body(
        text: Self.shortened(text, to: limit),
        quotedText: nil,
        omittedQuotedCharacters: nil
      )
    }
    let quotedAllowance = min(
      quoted.count,
      max(limit / Self.minimumQuotedShareDivisor, limit - text.count)
    )
    let newText = Self.shortened(text, to: limit - quotedAllowance)
    let quotedText = String(quoted.prefix(limit - newText.count))
    return Body(
      text: newText,
      quotedText: quotedText,
      omittedQuotedCharacters: quoted.count - quotedText.count
    )
  }

  /// Bounded body text as presented to the model.
  struct Body {
    let text: String
    let quotedText: String?
    let omittedQuotedCharacters: Int?
  }

  private enum LineKind { case new, quoted }
}
