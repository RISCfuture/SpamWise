import Foundation

/// One entity of a message's MIME tree, read within the parser's limits.
struct MIMEPart {
  /// An unread part with no headers.
  static var skipped: Self {
    var issues = Set<DecodingIssue>()
    return Self(
      headers: [:],
      contentType: MIMEHeaderValue("", issues: &issues),
      disposition: MIMEHeaderValue("", issues: &issues),
      mediaType: "",
      content: .skipped
    )
  }

  /// Unfolded headers keyed by lowercase field name, in their byte-preserving raw form.
  var headers: [String: [String]]
  /// The parsed Content-Type; `text/plain` when the header is absent.
  var contentType: MIMEHeaderValue
  /// The parsed Content-Disposition; an empty token when the header is absent.
  var disposition: MIMEHeaderValue
  /// The lowercased media type, such as `text/html`; `text/plain` for a multipart read as text.
  var mediaType: String
  /// What the entity holds.
  var content: Content

  /// Whether the disposition explicitly asks mail clients to show the part as an attachment.
  var isExplicitAttachment: Bool { disposition.token == "attachment" }

  /// The lowercased Content-Transfer-Encoding, if declared.
  var transferEncoding: String? { headers["content-transfer-encoding"]?.first?.lowercased() }

  /// The contents of a MIME entity.
  enum Content {
    /// A leaf body, still transfer-encoded and byte-preserved.
    case leaf(String)
    /// The child entities of a multipart, in order.
    case multipart([MIMEPart])
    /// An entity left unread because its critical headers were ambiguous or a limit was reached.
    case skipped
  }
}

/**
 A message source read once into a ``MIMEPart`` tree, within byte, header, part and nesting
 limits.

 Only an oversized message or message header block throws. Every other structural problem
 degrades the affected entity and records a ``DecodingIssue``: ambiguous critical headers or
 boundary parameters skip that entity, parts beyond the part or nesting limit are skipped, and
 a multipart without a usable boundary is read as plain text.
 */
struct MIMETree {
  /// The message's own headers, kept even when its body is skipped.
  let headers: [String: [String]]
  /// The top-level entity.
  let root: MIMEPart
  /// Recoverable structural and header problems found while reading.
  let issues: Set<DecodingIssue>

  /// Reads a raw message, throwing only when the message or its header block is oversized.
  init(_ data: Data) throws {
    var reader = Reader()
    let split = try reader.split(try Reader.source(data), nested: false)
    root = reader.root(split)
    headers = split.headers
    issues = reader.issues
  }

  /// Decodes only the header fields of a complete message or of a header block without a body.
  static func headers(_ data: Data) throws -> [String: [String]] {
    var reader = Reader()
    let source = try Reader.source(data).replacingOccurrences(of: "\r", with: "\n")
    return try reader.split(source, nested: false).headers
  }
}

extension MIMETree {
  /// A header block and the body that follows it.
  private struct Split {
    var headers: [String: [String]]
    var body: String
    /// Whether a critical header was repeated, so the entity's content can't be read reliably.
    var ambiguous = false
  }

  /// The part count and issues accumulated while reading one message.
  private struct Reader {
    private static let maximumHeaderBytes = 65_536
    private static let maximumNestingDepth = 12
    private static let maximumParts = 128
    private static let maximumBoundaryCharacters = 200
    private static let criticalHeaders = [
      "content-type", "content-transfer-encoding", "content-disposition"
    ]
    private(set) var issues: Set<DecodingIssue> = []
    private var parts = 0

    /// Converts bytes to the parser's byte-preserving Latin-1 text with LF line endings.
    static func source(_ data: Data) throws -> String {
      guard data.count <= MIMEParser.maximumMessageBytes else { throw ParseError.tooLarge }
      return String(String.UnicodeScalarView(data.map(Unicode.Scalar.init)))
        .replacingOccurrences(of: "\r\n", with: "\n")
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

    /// Unfolds and indexes a header block, skipping unreadable fields and reporting whether any
    /// were.
    private static func fields(_ block: Substring) -> (
      headers: [String: [String]], complete: Bool
    ) {
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
     Splits a multipart body at delimiter lines that match `--boundary` or `--boundary--`
     exactly, apart from surrounding whitespace.

     A close delimiter before the first part is ignored, a missing close delimiter ends the
     final part at the end of the body, and a body with no delimiter at all is read as one
     headerless part.
     */
    private static func multipartBodies(
      _ raw: String,
      boundary: String,
      issues: inout Set<DecodingIssue>
    ) -> [String] {
      let opening = "--" + boundary, closing = opening + "--"
      var parts: [String] = [], current: [String]?
      for line in raw.components(separatedBy: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let opens = trimmed == opening, closes = trimmed == closing
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

    /**
     Separates headers from the body, noting whether the critical headers were ambiguous.

     A leading blank line means no headers, and a source without a blank line is all headers.
     Message headers must be within the header limit, and unreadable header lines are ignored.
     A nested part whose header block is oversized or begins with an unreadable line is read
     entirely as headerless plain text.
     */
    mutating func split(_ source: String, nested: Bool) throws -> Split {
      if source.hasPrefix("\n") { return Split(headers: [:], body: String(source.dropFirst())) }
      let separator = source.range(of: "\n\n")
      let block =
        separator.map { source[..<$0.lowerBound] }
        ?? source.dropLast(source.hasSuffix("\n") ? 1 : 0)
      guard block.utf8.count < Self.maximumHeaderBytes else {
        guard nested else { throw ParseError.tooLarge }
        return headerless(source)
      }
      let (headers, complete) = Self.fields(block)
      if !complete {
        guard !nested || Self.field(String(block.prefix { $0 != "\n" })) != nil else {
          return headerless(source)
        }
        issues.insert(nested ? .malformedPartHeaders : .malformedMessageHeaders)
      }
      let body = separator.map { String(source[$0.upperBound...]) } ?? ""
      let ambiguous = !Self.criticalHeaders.allSatisfy { (headers[$0]?.count ?? 0) <= 1 }
      if ambiguous { issues.insert(.ambiguousPartHeaders) }
      return Split(headers: headers, body: body, ambiguous: ambiguous)
    }

    /// Reads the top-level entity from the message's own header split.
    mutating func root(_ split: Split) -> MIMEPart {
      parts = 1
      return entity(split, depth: 0)
    }

    private mutating func headerless(_ source: String) -> Split {
      issues.insert(.malformedPartHeaders)
      return Split(headers: [:], body: source)
    }

    /// Reads one nested part, or nil once the part limit has been reached.
    private mutating func part(_ source: String, depth: Int) -> MIMEPart? {
      parts += 1
      guard parts <= Self.maximumParts else {
        issues.insert(.partLimitExceeded)
        return nil
      }
      let split = (try? split(source, nested: true)) ?? headerless(source)
      return entity(split, depth: depth)
    }

    private mutating func entity(_ split: Split, depth: Int) -> MIMEPart {
      guard !split.ambiguous else { return .skipped }
      let contentType = MIMEHeaderValue(
        split.headers["content-type"]?.first ?? "text/plain",
        issues: &issues
      )
      var part = MIMEPart(
        headers: split.headers,
        contentType: contentType,
        disposition: MIMEHeaderValue(
          split.headers["content-disposition"]?.first ?? "",
          issues: &issues
        ),
        mediaType: contentType.token,
        content: .leaf(split.body)
      )
      guard part.mediaType.hasPrefix("multipart/") else { return part }
      let boundary = contentType.parameter("boundary")
      if boundary == .ambiguous {
        issues.insert(.ambiguousPartHeaders)
        part.content = .skipped
      } else if let value = boundary.value,
        (1...Self.maximumBoundaryCharacters).contains(value.count)
      {
        part.content = multipart(split.body, boundary: value, depth: depth)
      } else {
        issues.insert(.invalidMultipartBoundary)
        part.mediaType = "text/plain"
      }
      return part
    }

    private mutating func multipart(_ body: String, boundary: String, depth: Int)
      -> MIMEPart.Content
    {
      guard depth < Self.maximumNestingDepth else {
        issues.insert(.partLimitExceeded)
        return .skipped
      }
      var children: [MIMEPart] = []
      for source in Self.multipartBodies(body, boundary: boundary, issues: &issues) {
        guard let child = part(source, depth: depth + 1) else { break }
        children.append(child)
      }
      return .multipart(children)
    }
  }
}
