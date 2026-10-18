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
   Fits new and quoted text into `limit` characters.

   Quoted text receives at least a quarter of the limit, or all the room new text leaves, so a
   sender cannot hide the body by presenting it as a quotation.
   */
  func fitted(to limit: Int) -> Body {
    guard !quoted.isEmpty else {
      return Body(text: String(text.prefix(limit)), quotedText: nil, omittedQuotedCharacters: nil)
    }
    let quotedAllowance = min(
      quoted.count,
      max(limit / Self.minimumQuotedShareDivisor, limit - text.count)
    )
    let newText = String(text.prefix(limit - quotedAllowance))
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
