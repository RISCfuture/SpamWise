public import Foundation

/// Local text coverage for one declared attachment, independent of spam or malware evidence.
public struct AttachmentTextCoverage: Sendable, Equatable {
  /// The bounded, untrusted MIME labels identifying the attachment.
  public var attachment: AttachmentMetadata
  /// Whether this inspection could decode the declared attachment as bounded text.
  public var status: Status

  /// Describes text extraction only; none of these states establishes attachment safety.
  public enum Status: Sendable {
    /// Plain text or lexical HTML was decoded within the MIME parser's limits.
    case extracted
    /// The declared format requires an unavailable document decoder.
    case unsupported
    /// Decoding failed or exceeded a resource limit, leaving its content unknown.
    case unavailable
  }
}

/// A message with optional local attachment text and explicit coverage for unsupported content.
public struct DocumentInspection: Sendable {
  /// Body and successfully decoded attachment text, all untrusted.
  public var message: ParsedMessage
  /// Coverage follows MIME traversal order and never treats missing text as spam evidence.
  public var coverage: [AttachmentTextCoverage]

  /// Uses the existing bounded MIME parser; unreadable attachments preserve the body-only message.
  public init(raw: Data) throws {
    let original = try MIMEParser().parse(raw)
    let extracted = try? MIMEParser(includeTextAttachments: true).parse(raw)
    message = extracted ?? original
    coverage = (original.attachments ?? []).map { attachment in
      let supported = ["text/plain", "text/html"].contains(attachment.mediaType)
      return AttachmentTextCoverage(
        attachment: attachment,
        status: supported ? (extracted == nil ? .unavailable : .extracted) : .unsupported
      )
    }
  }
}
