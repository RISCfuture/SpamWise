import Foundation
import CryptoKit
public struct ParsedMessage: Codable, Sendable, Equatable {
    public var headers: [String: [String]]
    public var fromAddress: String
    public var fromDisplayName: String
    public var subject: String
    public var text: String
    public var urls: [String]
    public var hash: String
    public var messageID: String? { headers["message-id"]?.first }
    public func header(_ name: String) -> String? { headers[name.lowercased()]?.first }
}
public enum ParseError: Error, Sendable { case malformed, tooLarge, unsupportedCharset, invalidEncoding }
public func stableHash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
