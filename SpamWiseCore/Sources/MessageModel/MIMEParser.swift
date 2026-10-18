public import Foundation

/**
 Deliberately bounded subset of RFC 5322/MIME that degrades locally.

 A message is read once into a bounded part tree, from which body text, URLs, attachment labels
 and text, and embedded image payloads are derived in a single walk. Parsing fails only for a
 message or message header block over its size limit, or without a single readable sender;
 every other problem degrades the affected text and is recorded in
 ``ParsedMessage/decodingIssues``.
 */
public struct MIMEParser: Sendable {
  /// The largest raw message, in bytes, that SpamWise reads; larger messages stay unclassified.
  public static let maximumMessageBytes = 2_000_000
  private static let maximumTextCharacters = 100_000
  private static let maximumURLs = 40
  private static let maximumTextAttachmentBytes = 65_536
  private static let textMediaTypes: Set<String> = ["text/plain", "text/html"]
  private static let urlPattern = #"https?:[/\\]{2}[^\s<>"']+"#
  private static let urlTrailingPunctuation = CharacterSet(charactersIn: ".,);")
  private static let alternativesNotice =
    "MIME alternatives differ; the one mail apps display comes first, "
    + "and all following text is untrusted."
  private static let attachedTextNotice = "Untrusted attached text:\n"
  private let includeTextAttachments: Bool
  /// Creates a bounded parser with optional plain-text and HTML attachment extraction.
  public init(includeTextAttachments: Bool = false) {
    self.includeTextAttachments = includeTextAttachments
  }

  /// Extracts a normalized address from a header value holding exactly one mailbox.
  public static func address(_ value: String) -> String? { Mailbox(value)?.address }

  /**
   Joins distinct alternatives, each contiguous and within an equal share of the text limit.

   Alternatives run from last to first, because mail apps display the last one they support.
   */
  private static func alternativeText(_ texts: [String]) -> String {
    var seen: Set<String> = []
    let alternatives = texts.enumerated().reversed().filter { _, text in
      let normalized = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
      return !normalized.isEmpty && seen.insert(normalized).inserted
    }
    guard alternatives.count > 1 else { return alternatives.first?.element ?? "" }
    let share = maximumTextCharacters / alternatives.count
    return
      ([alternativesNotice]
      + alternatives.map { "[Alternative \($0.offset + 1)]\n" + $0.element.prefix(share) })
      .joined(separator: "\n")
  }

  /// Returns the declared character set, UTF-8 when absent, or nil when declared ambiguously.
  private static func charset(of part: MIMEPart) -> String? {
    let charset = part.contentType.parameter("charset")
    return charset == .absent ? "utf-8" : charset.value
  }

  /// Reads a URL candidate as a web URL with forward slashes, or nil when it has no host.
  private static func normalizedURL(_ candidate: String) -> String? {
    let url = candidate.trimmingCharacters(in: urlTrailingPunctuation)
      .replacingOccurrences(of: "\\", with: "/")
    return URL(string: url)?.host == nil ? nil : url
  }

  /**
   Decodes a message within byte, part, and nesting limits or throws.

   Throws ``ParseError/unreadableSender`` unless a single From header holds exactly one mailbox.
   */
  public func parse(_ data: Data) throws -> ParsedMessage { try inspect(data).message }

  /// Decodes only the header fields of a complete message or of a header block without a body.
  ///
  /// Header lines may end in CRLF, LF or a bare CR.
  public func headers(_ data: Data) throws -> [String: [String]] { try MIMETree.headers(data) }

  /// Reads the message once, deriving its text, attachment coverage and image payloads.
  func inspect(_ data: Data) throws -> DocumentInspection {
    let tree = try MIMETree(data)
    guard let from = tree.headers["from"], from.count == 1, let sender = Mailbox(from[0]) else {
      throw ParseError.unreadableSender
    }
    var extraction = Extraction(includeTextAttachments: includeTextAttachments, issues: tree.issues)
    let text = extraction.text(of: tree.root)
    let displayName = Self.decodeWords(sender.displayName, issues: &extraction.issues)
    let subject = Self.decodeWords(tree.headers["subject"]?.first ?? "", issues: &extraction.issues)
    let issues = DecodingIssue.allCases.filter(extraction.issues.contains)
    let message = ParsedMessage(
      headers: tree.headers,
      fromAddress: sender.address,
      fromDisplayName: displayName,
      subject: subject,
      text: String(text.prefix(Self.maximumTextCharacters)),
      urls: extraction.urls,
      hash: stableHash(data),
      attachments: extraction.attachments,
      decodingIssues: issues.isEmpty ? nil : issues
    )
    return DocumentInspection(
      message: message,
      coverage: extraction.coverage,
      images: extraction.images
    )
  }

  /// One walk over a message's part tree, accumulating everything derived from its leaves.
  private struct Extraction {
    let includeTextAttachments: Bool
    var issues: Set<DecodingIssue>
    /// Distinct URLs in order of first appearance, up to the URL limit.
    private(set) var urls: [String] = []
    private(set) var attachments: [AttachmentMetadata] = []
    private(set) var coverage: [AttachmentTextCoverage] = []
    private(set) var images: [InlineImage] = []
    private var seenURLs: Set<String> = []

    init(includeTextAttachments: Bool, issues: Set<DecodingIssue>) {
      self.includeTextAttachments = includeTextAttachments
      self.issues = issues
    }

    mutating func text(of part: MIMEPart) -> String {
      switch part.content {
        case .skipped: return ""
        case .leaf(let body): return leafText(part, body: body)
        case .multipart(let children):
          let texts = children.map { text(of: $0) }
          return part.mediaType == "multipart/alternative"
            ? MIMEParser.alternativeText(texts)
            : texts.filter { !$0.isEmpty }.joined(separator: "\n")
      }
    }

    /**
     Returns a leaf's body text, recording its attachment label and coverage.

     Text parts are body text unless their disposition is explicitly `attachment`; attached text
     is included only when attachment extraction is on and the part is within its size limit.
     */
    private mutating func leafText(_ part: MIMEPart, body: String) -> String {
      let attachment = attachmentMetadata(part)
      if part.mediaType.hasPrefix("image/"), part.transferEncoding == "base64" {
        images.append(InlineImage(mediaType: part.mediaType, encoded: body))
      }
      guard MIMEParser.textMediaTypes.contains(part.mediaType) else {
        record(attachment, .unsupported)
        return ""
      }
      guard part.isExplicitAttachment else {
        record(attachment, .extracted)
        return decodedText(part, body: body)
      }
      guard includeTextAttachments else {
        record(attachment, .omitted)
        return ""
      }
      guard body.utf8.count <= MIMEParser.maximumTextAttachmentBytes else {
        record(attachment, .unavailable)
        return ""
      }
      record(attachment, .extracted)
      return MIMEParser.attachedTextNotice + decodedText(part, body: body)
    }

    private mutating func record(
      _ attachment: AttachmentMetadata?,
      _ status: AttachmentTextCoverage.Status
    ) {
      guard let attachment else { return }
      attachments.append(attachment)
      coverage.append(.init(attachment: attachment, status: status))
    }

    /// Labels a part shown as an attachment, named, or of an `application/` type.
    private mutating func attachmentMetadata(_ part: MIMEPart) -> AttachmentMetadata? {
      let filename = part.disposition.parameter("filename")
      let name = part.contentType.parameter("name")
      guard
        part.isExplicitAttachment || filename != .absent || name != .absent
          || part.mediaType.hasPrefix("application/")
      else { return nil }
      if filename == .ambiguous || (filename == .absent && name == .ambiguous) {
        issues.insert(.ambiguousPartHeaders)
      }
      let label = filename == .absent ? name : filename
      return AttachmentMetadata(mediaType: part.mediaType, filename: label.text(issues: &issues))
    }

    private mutating func decodedText(_ part: MIMEPart, body: String) -> String {
      let decoded = MIMEParser.decode(
        MIMEParser.transferDecoded(body, encoding: part.transferEncoding, issues: &issues),
        charset: MIMEParser.charset(of: part),
        issues: &issues
      )
      guard part.mediaType == "text/html" else {
        collectURLs(in: decoded)
        return decoded.trimmingCharacters(in: .whitespacesAndNewlines)
      }
      let html = HTMLText.convert(decoded, limit: MIMEParser.maximumTextCharacters)
      collectURLs(in: html.linkSource)
      return html.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private mutating func collectURLs(in text: String) {
      guard urls.count < MIMEParser.maximumURLs,
        let expression = try? NSRegularExpression(
          pattern: MIMEParser.urlPattern,
          options: .caseInsensitive
        )
      else { return }
      for match in expression.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
        guard let range = Range(match.range, in: text),
          let url = MIMEParser.normalizedURL(String(text[range])), seenURLs.insert(url).inserted
        else { continue }
        urls.append(url)
        if urls.count == MIMEParser.maximumURLs { return }
      }
    }
  }
}
