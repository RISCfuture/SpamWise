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
  /// RFC Message-ID claim, which is not globally unique or trusted.
  public var messageID: String? { headers["message-id"]?.first }
  /// Returns the first value for a case-insensitive header name.
  public func header(_ name: String) -> String? { headers[name.lowercased()]?.first }
}
/// A malformed or over-budget message that must remain unclassified.
public enum ParseError: Error, Sendable {
  case malformed, tooLarge, unsupportedCharset, invalidEncoding
}
/// Returns the lowercase hexadecimal SHA-256 digest of the supplied bytes.
public func stableHash(_ data: Data) -> String {
  SHA256.hash(data: data).map { ($0 < 16 ? "0" : "") + String($0, radix: 16) }.joined()
}
