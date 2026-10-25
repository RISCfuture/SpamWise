public import Foundation

/// Local text coverage for one declared attachment, independent of spam or malware evidence.
public struct AttachmentTextCoverage: Sendable, Equatable {
  /// The bounded, untrusted MIME labels identifying the attachment.
  public var attachment: AttachmentMetadata
  /// Whether this inspection could decode the declared attachment as bounded text.
  public var status: Status

  /// Describes text extraction only; none of these states establishes attachment safety.
  public enum Status: Sendable {
    /// Plain text, lexical HTML or an encapsulated message was decoded within the MIME parser's
    /// limits.
    case extracted
    /// Attached plain text, HTML or a message was left out because attachment text extraction is
    /// off.
    case omitted
    /// The declared format requires an unavailable document decoder.
    case unsupported
    /// Decoding exceeded a resource limit, leaving its content unknown.
    case unavailable
  }
}

/// An embedded base64 image part, decoded only on request and not yet validated as an image.
public struct InlineImage: Sendable, Equatable {
  private static let base64CharactersPerGroup = 4
  private static let bytesPerGroup = 3
  /// The declared lowercased media type, such as `image/png`.
  public let mediaType: String
  /// The part's body, still base64-encoded.
  let encoded: String

  /// Decodes the payload when it is valid base64 of at most `maximumBytes` bytes.
  func data(maximumBytes: Int) -> Data? {
    let compact = encoded.filter { !$0.isWhitespace }
    let maximumGroups = (maximumBytes + Self.bytesPerGroup - 1) / Self.bytesPerGroup
    guard compact.utf8.count <= maximumGroups * Self.base64CharactersPerGroup,
      let data = Data(base64Encoded: compact), data.count <= maximumBytes
    else { return nil }
    return data
  }
}

/// A message read once, with attachment text coverage and its embedded image parts.
public struct DocumentInspection: Sendable {
  /// Body text, plus attachment text when extraction is on; all untrusted.
  public var message: ParsedMessage
  /// Coverage of each attachment in MIME order; missing text is never treated as spam evidence.
  public var coverage: [AttachmentTextCoverage]
  /// Embedded base64 image parts in MIME order, for optional local text recognition.
  public var images: [InlineImage]

  /**
   Parses a message once within the MIME parser's limits.

   An attachment that can't be read only marks its own coverage, preserving the rest of the
   message.

   - Parameters:
     - raw: The message source.
     - includeTextAttachments: Whether attached plain text, HTML and messages join the message
       text.
   - Throws: ``ParseError`` when the message can't be parsed at all.
   */
  public init(raw: Data, includeTextAttachments: Bool = true) throws {
    self = try MIMEParser(includeTextAttachments: includeTextAttachments).inspect(raw)
  }

  init(message: ParsedMessage, coverage: [AttachmentTextCoverage], images: [InlineImage]) {
    self.message = message; self.coverage = coverage; self.images = images
  }
}
