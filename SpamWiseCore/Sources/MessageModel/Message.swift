public import Foundation
import CryptoKit
/// Decoded message content; URLs are extracted without fetching remote resources.
public struct ParsedMessage: Codable, Sendable, Equatable {
  /**
   Unfolded headers keyed by lowercase field name, preserving repeated fields.

   Values are undecoded: each holds one character per raw header byte, so RFC 2047 encoded words
   stay encoded and raw UTF-8 reads as Latin-1. Use ``decodedHeaders(_:)`` for text to display
   or match.
   */
  public var headers: [String: [String]]
  /// Normalized sender email address.
  public var fromAddress: String
  /// Decoded sender display name; this is an untrusted claim.
  public var fromDisplayName: String
  /// Decoded message subject; empty when the message has none.
  public var subject: String
  /**
   Decoded body text with remote resources excluded.

   Differing `multipart/alternative` parts each appear whole, under an `[Alternative N]` marker.
   */
  public var text: String
  /// Distinct extracted URLs in order of first appearance, at most 40, never fetched.
  public var urls: [String]
  /// SHA-256 digest of the original message bytes.
  public var hash: String
  /// Bounded attachment header claims; names are never interpreted as local paths.
  public var attachments: [AttachmentMetadata]?
  /// Recoverable decoding problems in ``DecodingIssue`` case order; nil when decoding was clean.
  public var decodingIssues: [DecodingIssue]?
  /// RFC Message-ID claim, which is not globally unique or trusted.
  public var messageID: String? { headers["message-id"]?.first }
  /// Decoded comments of the From mailbox; like the display name, an untrusted claim.
  public var fromComments: String {
    var issues = Set<DecodingIssue>()
    return header("from").flatMap(Mailbox.init).map {
      MIMEParser.decodeWords($0.comments, issues: &issues)
    } ?? ""
  }
  /// Whether a decoding issue left part of the message unread, so mail apps may show more.
  public var concealsContent: Bool { decodingIssues?.contains(where: \.concealsContent) == true }
  /// Returns the first undecoded value for a case-insensitive header name; see ``headers``.
  public func header(_ name: String) -> String? { headers[name.lowercased()]?.first }
  /**
   Returns every value of a case-insensitive header name as text.

   RFC 2047 encoded words are decoded, and other bytes read as UTF-8 when they are valid.
   */
  public func decodedHeaders(_ name: String) -> [String] {
    var issues = Set<DecodingIssue>()
    return (headers[name.lowercased()] ?? []).map { MIMEParser.decodeWords($0, issues: &issues) }
  }
}
/// A recoverable decoding problem; the affected text was decoded lossily instead of rejected.
public enum DecodingIssue: String, Codable, Sendable, CaseIterable {
  /// Bytes were invalid for the declared character set and were replaced or reinterpreted.
  case invalidCharacters
  /// The character set was unknown or ambiguous, so text was decoded as UTF-8 or Windows-1252.
  case unknownCharset
  /// A quoted-printable escape was invalid and kept literally.
  case invalidQuotedPrintable
  /// Base64 content had characters outside the alphabet, data after padding or an incomplete group.
  case invalidBase64
  /// An RFC 2047 encoded word could not be decoded and was kept verbatim.
  case invalidEncodedWord
  /// A part declared an unknown transfer encoding and was read as 8-bit text.
  case unknownTransferEncoding
  /// A nested part had unreadable header lines, which were ignored or, when the part began with
  /// one, read with the rest of the part as plain text.
  case malformedPartHeaders
  /// The message or a part repeated its Content-Type, Content-Transfer-Encoding or
  /// Content-Disposition header, or its multipart boundary, and its content was skipped; or a
  /// part repeated its filename, which was dropped.
  case ambiguousPartHeaders
  /// Unreadable message header lines were ignored.
  case malformedMessageHeaders
  /// A multipart body closed before its first part or lacked a delimiter; the early close was
  /// ignored and a missing delimiter left the rest of the body in the final part.
  case incompleteMultipart
  /// A multipart body had no usable boundary parameter and was read as plain text.
  case invalidMultipartBoundary
  /// The message had more than 128 parts or nesting deeper than 12 levels; the rest was skipped.
  case partLimitExceeded

  /// Whether the issue left content unread or misread its structure, where mail apps may differ.
  public var concealsContent: Bool {
    switch self {
      case .ambiguousPartHeaders, .invalidMultipartBoundary, .partLimitExceeded: true
      default: false
    }
  }
}
/// Untrusted attachment labels extracted without opening attachment content.
public struct AttachmentMetadata: Codable, Sendable, Equatable {
  /// Declared MIME type, independent of filename extension.
  public var mediaType: String
  /// Declared filename, bounded to 256 characters.
  public var filename: String?
  /// Creates untrusted metadata for explicit user rules.
  public init(mediaType: String, filename: String?) {
    self.mediaType = String(mediaType.prefix(256))
    self.filename = filename.map { String($0.prefix(256)) }
  }
}
/// Failures that prevent safe interpretation of message content.
public protocol MessageParsingError: Error {}

/// An over-budget message, or one without a readable sender, that can't be interpreted safely.
public enum ParseError: MessageParsingError, Sendable, LocalizedError {
  /// The message, its header block or other bounded content exceeds a resource limit.
  case tooLarge
  /// The From header is missing, repeated or not exactly one valid mailbox.
  case unreadableSender

  /// General description of the parsing failure.
  public var errorDescription: String? { String(localized: "Couldn’t read the message.") }

  /// The unsupported content or resource limit that prevented parsing.
  public var failureReason: String? {
    switch self {
      case .tooLarge: String(localized: "The message exceeds the supported content limits.")
      case .unreadableSender:
        String(localized: "The message has no single readable sender address.")
    }
  }
}
/// Returns the lowercase hexadecimal SHA-256 digest of the supplied bytes.
public func stableHash(_ data: Data) -> String {
  SHA256.hash(data: data).map { ($0 < 16 ? "0" : "") + String($0, radix: 16) }.joined()
}
