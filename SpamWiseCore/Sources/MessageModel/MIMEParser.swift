public import Foundation

/// Deliberately bounded subset of RFC 5322/MIME. Unsupported or ambiguous mail is unclassified.
public struct MIMEParser: Sendable {
  private static let maximumMessageBytes = 2_000_000
  private static let maximumTextCharacters = 100_000
  private static let maximumHeaderBytes = 65_536
  private static let maximumNestingDepth = 12
  private static let maximumParts = 128
  private static let maximumBoundaryCharacters = 200
  private static let alternativeChunkCharacters = 128
  private static let maximumURLs = 40
  private static let maximumTextAttachmentBytes = 65_536
  private let includeTextAttachments: Bool
  /// Creates a bounded parser with optional plain-text and HTML attachment extraction.
  public init(includeTextAttachments: Bool = false) {
    self.includeTextAttachments = includeTextAttachments
  }

  /// Extracts a normalized address from a header value holding exactly one mailbox.
  public static func address(_ value: String) -> String? { Mailbox(value)?.address }

  private static func alternativeText(_ contents: [Content]) -> String {
    var seen: Set<String> = []
    var alternatives = contents.compactMap { content -> Substring? in
      let normalized = content.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
      guard !normalized.isEmpty, seen.insert(normalized).inserted else { return nil }
      return content.text.prefix(Self.maximumTextCharacters)
    }
    guard alternatives.count > 1 else { return alternatives.first.map(String.init) ?? "" }
    var result = "MIME alternatives differ; all following text is untrusted.\n"
    while alternatives.contains(where: { !$0.isEmpty }), result.count < Self.maximumTextCharacters {
      for index in alternatives.indices where !alternatives[index].isEmpty {
        result +=
          "[Alternative \(index + 1)] "
          + alternatives[index].prefix(Self.alternativeChunkCharacters) + "\n"
        alternatives[index] = alternatives[index].dropFirst(Self.alternativeChunkCharacters)
      }
    }
    return String(result.prefix(Self.maximumTextCharacters))
  }

  /// Returns every value of a Content-Type or Content-Disposition parameter, in order.
  static func parameterValues(_ key: String, in value: String) -> [String] {
    matches(
      "(?:^|;)\\s*" + key + #"\s*=\s*(?:"([^"]*)"|([^;\s]+))"#,
      value,
      options: .caseInsensitive
    ).map { $0[1].isEmpty ? $0[2] : $0[1] }
  }
  private static func attachmentMetadata(
    _ headers: [String: [String]],
    contentType: String,
    mime: String,
    issues: inout Set<DecodingIssue>
  ) -> [AttachmentMetadata] {
    let disposition = headers["content-disposition"]?.first ?? ""
    let filename =
      parameterValues("filename", in: disposition).first
      ?? parameterValues("name", in: contentType).first
    guard
      disposition.lowercased().hasPrefix("attachment") || filename != nil
        || mime.hasPrefix("application/")
    else { return [] }
    return [.init(mediaType: mime, filename: filename.map { decodeWords($0, issues: &issues) })]
  }
  private static func matches(
    _ pattern: String,
    _ text: String,
    options: NSRegularExpression.Options = []
  ) -> [[String]] {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
      return []
    }
    return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
      (0..<match.numberOfRanges).map {
        Range(match.range(at: $0), in: text).map { String(text[$0]) } ?? ""
      }
    }
  }
  /// Splits a header line into its lowercased name and trimmed value, allowing obsolete
  /// whitespace before the colon.
  private static func field(_ line: String) -> (name: String, value: String)? {
    guard let colon = line.firstIndex(of: ":") else { return nil }
    var name = line[..<colon]
    while name.last == " " || name.last == "\t" { name = name.dropLast() }
    guard !name.isEmpty, name.utf8.allSatisfy({ $0 > 32 && $0 < 127 }) else { return nil }
    return (
      name.lowercased(),
      String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
    )
  }
  /// Unfolds and indexes a header block, skipping unreadable fields and reporting whether any were.
  private static func fields(_ block: Substring) -> (headers: [String: [String]], complete: Bool) {
    var lines: [String] = [], complete = true
    for line in block.components(separatedBy: "\n") where !line.isEmpty {
      if line.first == " " || line.first == "\t" {
        guard !lines.isEmpty else {
          complete = false
          continue
        }
        lines[lines.count - 1] += " " + line.trimmingCharacters(in: .whitespaces)
      } else {
        lines.append(line)
      }
    }
    var headers: [String: [String]] = [:]
    for line in lines {
      guard let field = field(line) else {
        complete = false
        continue
      }
      headers[field.name, default: []].append(field.value)
    }
    return (headers, complete)
  }
  /**
   Splits a multipart body at its boundary delimiters.

   A close delimiter before the first part is ignored, a missing close delimiter ends the
   final part at the end of the body, and a body with no delimiter at all is read as one
   headerless part.
   */
  private static func multipartBodies(
    _ raw: String,
    boundary: String,
    issues: inout Set<DecodingIssue>
  ) -> [String] {
    var parts: [String] = [], current: [String]?
    for line in raw.components(separatedBy: "\n") {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      let opens = trimmed == "--" + boundary, closes = trimmed == "--" + boundary + "--"
      if closes, current == nil {
        issues.insert(.incompleteMultipart)
      } else if opens || closes {
        if let current { parts.append(current.joined(separator: "\n")) }
        guard opens else { return parts }
        current = []
      } else {
        current?.append(line)
      }
    }
    issues.insert(.incompleteMultipart)
    return parts + [current.map { $0.joined(separator: "\n") } ?? "\n" + raw]
  }
  private static func headerless(_ source: String, issues: inout Set<DecodingIssue>) -> (
    [String: [String]], String
  ) {
    issues.insert(.malformedPartHeaders)
    return ([:], source)
  }
  private static func transferDecoded(
    _ raw: String,
    encoding: String?,
    issues: inout Set<DecodingIssue>
  ) -> Data {
    switch encoding?.lowercased() ?? "8bit" {
      case "base64": return base64(raw, issues: &issues)
      case "quoted-printable": return quotedPrintable(raw, issues: &issues)
      case "7bit", "8bit", "binary": return Data(latin1Bytes(raw))
      default:
        issues.insert(.unknownTransferEncoding)
        return Data(latin1Bytes(raw))
    }
  }
  /// Returns the single usable multipart boundary, or nil when it is missing, empty or over-long.
  private static func boundary(of contentType: String) throws -> String? {
    let boundaries = parameterValues("boundary", in: contentType)
    guard boundaries.count <= 1 else { throw ParseError.malformed }
    return boundaries.first.flatMap {
      (1...maximumBoundaryCharacters).contains($0.count) ? $0 : nil
    }
  }
  /// Returns the declared character set, UTF-8 when absent, or nil when declared more than once.
  private static func charset(of contentType: String) -> String? {
    let charsets = parameterValues("charset", in: contentType)
    return charsets.count > 1 ? nil : charsets.first ?? "utf-8"
  }

  private static func source(_ data: Data) throws -> String {
    guard data.count <= maximumMessageBytes else { throw ParseError.tooLarge }
    // A byte-preserving intermediate avoids corrupting non-UTF8 MIME parts.
    return String(data.map { Character(UnicodeScalar($0)) }).replacingOccurrences(
      of: "\r\n",
      with: "\n"
    )
  }
  /**
   Decodes a message within byte, part, and nesting limits or throws.

   Throws ``ParseError/unreadableSender`` unless a single From header holds exactly one mailbox.
   */
  public func parse(_ data: Data) throws -> ParsedMessage {
    let source = try Self.source(data)
    var traversal = Traversal()
    let (headers, _) = try split(source, traversal: &traversal)
    guard let from = headers["from"], from.count == 1, let sender = Mailbox(from[0]) else {
      throw ParseError.unreadableSender
    }
    let content = try part(source, depth: 0, traversal: &traversal)
    let displayName = Self.decodeWords(sender.displayName, issues: &traversal.issues)
    let subject = Self.decodeWords(headers["subject"]?.first ?? "", issues: &traversal.issues)
    let issues = DecodingIssue.allCases.filter(traversal.issues.contains)
    return ParsedMessage(
      headers: headers,
      fromAddress: sender.address,
      fromDisplayName: displayName,
      subject: subject,
      text: String(content.text.prefix(Self.maximumTextCharacters)),
      urls: Array(content.urls.uniqued().prefix(Self.maximumURLs)),
      hash: stableHash(data),
      attachments: content.attachments,
      decodingIssues: issues.isEmpty ? nil : issues
    )
  }

  /// Decodes only the header fields of a complete message or of a header block without a body.
  ///
  /// Header lines may end in CRLF, LF or a bare CR.
  public func headers(_ data: Data) throws -> [String: [String]] {
    var traversal = Traversal()
    let source = try Self.source(data).replacingOccurrences(of: "\r", with: "\n")
    return try split(source, traversal: &traversal).0
  }

  /**
   Separates headers from the body, throwing for ambiguous critical message headers.

   A leading blank line means no headers, and a source without a blank line is all headers.
   Message headers must be within the header limit, and unreadable header lines are ignored.
   A nested part whose header block is oversized or begins with an unreadable line is read
   entirely as headerless plain text, and one with ambiguous critical headers is empty.
   */
  private func split(_ source: String, nested: Bool = false, traversal: inout Traversal) throws
    -> ([String: [String]], String)
  {
    if source.hasPrefix("\n") { return ([:], String(source.dropFirst())) }
    let separator = source.range(of: "\n\n")
    let block =
      separator.map { source[..<$0.lowerBound] } ?? source.dropLast(source.hasSuffix("\n") ? 1 : 0)
    guard block.utf8.count < Self.maximumHeaderBytes else {
      guard nested else { throw ParseError.tooLarge }
      return Self.headerless(source, issues: &traversal.issues)
    }
    let (headers, complete) = Self.fields(block)
    if !complete {
      guard !nested || Self.field(String(block.prefix { $0 != "\n" })) != nil else {
        return Self.headerless(source, issues: &traversal.issues)
      }
      traversal.issues.insert(nested ? .malformedPartHeaders : .malformedMessageHeaders)
    }
    for key in ["content-type", "content-transfer-encoding", "content-disposition"]
    where (headers[key]?.count ?? 0) > 1 {
      guard nested else { throw ParseError.malformed }
      traversal.issues.insert(.ambiguousPartHeaders)
      return ([:], "")
    }
    return (headers, separator.map { String(source[$0.upperBound...]) } ?? "")
  }
  private func part(_ source: String, depth: Int, traversal: inout Traversal) throws -> Content {
    traversal.parts += 1
    guard depth <= Self.maximumNestingDepth, traversal.parts <= Self.maximumParts else {
      throw ParseError.tooLarge
    }
    let (headers, raw) = try split(source, nested: depth > 0, traversal: &traversal)
    let contentType = headers["content-type"]?.first ?? "text/plain"
    var mime = contentType.components(separatedBy: ";")[0].lowercased().trimmingCharacters(
      in: .whitespaces
    )
    let attachments = Self.attachmentMetadata(
      headers,
      contentType: contentType,
      mime: mime,
      issues: &traversal.issues
    )
    let isAttachment = !attachments.isEmpty
    if isAttachment {
      guard includeTextAttachments, ["text/plain", "text/html"].contains(mime) else {
        return Content(text: "", urls: [], plain: false, attachments: attachments)
      }
      guard raw.utf8.count <= Self.maximumTextAttachmentBytes else { throw ParseError.tooLarge }
    }
    if mime.hasPrefix("multipart/") {
      guard depth == 0 || Self.parameterValues("boundary", in: contentType).count <= 1 else {
        traversal.issues.insert(.ambiguousPartHeaders)
        return Content(text: "", urls: [], plain: false)
      }
      if let boundary = try Self.boundary(of: contentType) {
        return try multipart(
          raw,
          mime: mime,
          boundary: boundary,
          depth: depth,
          traversal: &traversal
        )
      }
      traversal.issues.insert(.invalidMultipartBoundary)
      mime = "text/plain"
    }
    guard ["text/plain", "text/html"].contains(mime) else {
      return Content(text: "", urls: [], plain: false)
    }
    let decoded = Self.decode(
      Self.transferDecoded(
        raw,
        encoding: headers["content-transfer-encoding"]?.first,
        issues: &traversal.issues
      ),
      charset: Self.charset(of: contentType),
      issues: &traversal.issues
    )
    var urls = Self.matches(#"https?://[^\s<>"']+"#, decoded, options: .caseInsensitive).map {
      $0[0].trimmingCharacters(in: CharacterSet(charactersIn: ".,);"))
    }
    let text =
      mime == "text/html"
      ? HTMLText.text(from: decoded, limit: Self.maximumTextCharacters) : decoded
    urls = urls.filter { URL(string: $0)?.host != nil }
    return Content(
      text: (isAttachment ? "Untrusted attached text:\n" : "")
        + text.trimmingCharacters(in: .whitespacesAndNewlines),
      urls: urls,
      plain: mime == "text/plain",
      attachments: attachments
    )
  }
  private func multipart(
    _ raw: String,
    mime: String,
    boundary: String,
    depth: Int,
    traversal: inout Traversal
  ) throws -> Content {
    let parts = Self.multipartBodies(raw, boundary: boundary, issues: &traversal.issues)
    var contents: [Content] = []
    for source in parts {
      contents.append(try part(source, depth: depth + 1, traversal: &traversal))
    }
    return Content(
      text: mime == "multipart/alternative"
        ? Self.alternativeText(contents) : contents.map(\.text).joined(separator: "\n"),
      urls: contents.flatMap(\.urls),
      plain: contents.contains(where: \.plain),
      attachments: contents.flatMap(\.attachments)
    )
  }

  /// Mutable state shared across one message's MIME traversal.
  private struct Traversal {
    var parts = 0
    var issues: Set<DecodingIssue> = []
  }

  private struct Content {
    var text: String
    var urls: [String]
    var plain: Bool
    var attachments: [AttachmentMetadata] = []
  }
}
