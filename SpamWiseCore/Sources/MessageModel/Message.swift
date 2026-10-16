public import Foundation
import CryptoKit
/// Decoded message content; URLs are extracted without fetching remote resources.
public struct ParsedMessage: Codable, Sendable, Equatable {
  /// Unfolded headers keyed by lowercase field name, preserving repeated fields.
  public var headers: [String: [String]]
  /// Normalized sender email address.
  public var fromAddress: String
  /// Decoded sender display name; this is an untrusted claim.
  public var fromDisplayName: String
  /// Decoded message subject.
  public var subject: String
  /// Decoded body text with remote resources excluded.
  public var text: String
  /// Extracted URLs, never fetched during parsing.
  public var urls: [String]
  /// SHA-256 digest of the original message bytes.
  public var hash: String
  /// Bounded attachment header claims; names are never interpreted as local paths.
  public var attachments: [AttachmentMetadata]?
  /// RFC Message-ID claim, which is not globally unique or trusted.
  public var messageID: String? { headers["message-id"]?.first }
  /// Returns the first value for a case-insensitive header name.
  public func header(_ name: String) -> String? { headers[name.lowercased()]?.first }
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

/// A malformed or over-budget message that must remain unclassified.
public enum ParseError: MessageParsingError, Sendable, LocalizedError {
  case malformed, tooLarge, unsupportedCharset, invalidEncoding

  /// General description of the parsing failure.
  public var errorDescription: String? { String(localized: "Couldn’t read the message.") }

  /// The unsupported content or resource limit that prevented parsing.
  public var failureReason: String? {
    switch self {
      case .malformed: String(localized: "The message structure is invalid or ambiguous.")
      case .tooLarge: String(localized: "The message exceeds the supported content limits.")
      case .unsupportedCharset: String(localized: "The message uses an unsupported character set.")
      case .invalidEncoding: String(localized: "The message contains invalid encoded content.")
    }
  }
}
/// Returns the lowercase hexadecimal SHA-256 digest of the supplied bytes.
public func stableHash(_ data: Data) -> String {
  SHA256.hash(data: data).map { ($0 < 16 ? "0" : "") + String($0, radix: 16) }.joined()
}
