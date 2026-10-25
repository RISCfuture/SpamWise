import CoreFoundation
import Foundation

/// Lossy content decoding: malformed bytes degrade the affected text and record an issue.
extension MIMEParser {
  private static let equalsSign = UInt8(ascii: "=")
  private static let lineFeed = UInt8(ascii: "\n")
  private static let base64GroupLength = 4
  private static let base64BitsPerCharacter = 6
  private static let base64BufferMask: UInt32 = 0xFFFF
  private static let base64Values = Dictionary(
    uniqueKeysWithValues: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8
      .enumerated().map { ($1, UInt32($0)) }
  )
  private static let encodedWordPattern = #"=\?([^?]+)\?([bBqQ])\?([^?]*)\?="#

  /**
   Decodes text in its declared character set, falling back to UTF-8 then Windows-1252.

   A nil character set means the declaration was ambiguous and is treated as unknown.
   */
  static func decode(_ data: Data, charset: String?, issues: inout Set<DecodingIssue>) -> String {
    guard let charset else {
      issues.insert(.unknownCharset)
      return fallbackText(data)
    }
    let characterSet = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
    guard characterSet != kCFStringEncodingInvalidId else {
      issues.insert(.unknownCharset)
      return fallbackText(data)
    }
    let encoding = String.Encoding(
      rawValue: CFStringConvertEncodingToNSStringEncoding(characterSet)
    )
    if let text = String(data: data, encoding: encoding) { return text }
    issues.insert(.invalidCharacters)
    // Replacing only the invalid bytes keeps the rest of a declared UTF-8 body readable, and
    // `issues` reports the repair.
    // swiftlint:disable:next optional_data_string_conversion
    return encoding == .utf8 ? String(decoding: data, as: UTF8.self) : fallbackText(data)
  }

  /// Decodes text without a declared character set as UTF-8 when it is valid, otherwise as
  /// Windows-1252, recording the invalid UTF-8.
  static func undeclaredText(_ data: Data, issues: inout Set<DecodingIssue>) -> String {
    if let text = String(data: data, encoding: .utf8) { return text }
    issues.insert(.invalidCharacters)
    return fallbackText(data)
  }

  /// Removes a part's transfer encoding, reading an unknown encoding as 8-bit text.
  static func transferDecoded(
    _ raw: String,
    encoding: String?,
    issues: inout Set<DecodingIssue>
  ) -> Data {
    switch encoding ?? "8bit" {
      case "base64": return base64(raw, issues: &issues)
      case "quoted-printable": return quotedPrintable(raw, issues: &issues)
      case "7bit", "8bit", "binary": return Data(latin1Bytes(raw))
      default:
        issues.insert(.unknownTransferEncoding)
        return Data(latin1Bytes(raw))
    }
  }

  /// Decodes quoted-printable text, keeping invalid escapes literally.
  static func quotedPrintable(_ source: String, issues: inout Set<DecodingIssue>) -> Data {
    let bytes = latin1Bytes(source)
    var result = Data(), index = 0
    while index < bytes.count {
      guard bytes[index] == equalsSign else {
        result.append(bytes[index]); index += 1
        continue
      }
      if let next = softLineBreakEnd(bytes, equalsSignAt: index) {
        index = next
      } else if index + 2 < bytes.count, let high = hexValue(bytes[index + 1]),
        let low = hexValue(bytes[index + 2])
      {
        result.append(high << 4 | low); index += 3
      } else {
        issues.insert(.invalidQuotedPrintable)
        result.append(bytes[index]); index += 1
      }
    }
    return result
  }

  /**
   Decodes base64 group by group, accepting missing final padding and padding inside the stream.

   Characters outside the alphabet, data after padding and an incomplete group are recorded.
   */
  static func base64(_ source: some StringProtocol, issues: inout Set<DecodingIssue>) -> Data {
    var result = Data(), buffer: UInt32 = 0, bufferedBits = 0, groupLength = 0, padded = false
    for byte in latin1Bytes(source) where !isWhitespace(byte) {
      if let value = base64Values[byte] {
        if padded { issues.insert(.invalidBase64); padded = false }
        buffer = (buffer << base64BitsPerCharacter | value) & base64BufferMask
        bufferedBits += base64BitsPerCharacter
        groupLength = (groupLength + 1) % base64GroupLength
        if bufferedBits >= UInt8.bitWidth {
          bufferedBits -= UInt8.bitWidth
          result.append(UInt8(truncatingIfNeeded: buffer >> bufferedBits))
        }
      } else if byte == equalsSign {
        if groupLength == 1 { issues.insert(.invalidBase64) }
        bufferedBits = 0; groupLength = 0; padded = true
      } else {
        issues.insert(.invalidBase64)
      }
    }
    if groupLength == 1 { issues.insert(.invalidBase64) }
    return result
  }

  /**
   Decodes RFC 2047 encoded words, keeping undecodable words verbatim.

   Whitespace between two adjacent encoded words is dropped, as RFC 2047 requires, and text
   outside encoded words is read as UTF-8 when it is valid.
   */
  static func decodeWords(_ value: String, issues: inout Set<DecodingIssue>) -> String {
    guard value.contains("=?") else { return unencodedHeader(value, issues: &issues) }
    guard let regex = try? NSRegularExpression(pattern: encodedWordPattern) else { return value }
    var result = "", position = value.startIndex, previousWasEncoded = false
    for match in regex.matches(in: value, range: NSRange(value.startIndex..., in: value)) {
      guard let range = Range(match.range, in: value) else { continue }
      func field(_ number: Int) -> String {
        Range(match.range(at: number), in: value).map { String(value[$0]) } ?? ""
      }
      let gap = value[position..<range.lowerBound]
      if !(previousWasEncoded && gap.allSatisfy(\.isFoldingWhitespace)) {
        result += unencodedHeader(String(gap), issues: &issues)
      }
      if let decoded = encodedWord(charset: field(1), encoding: field(2), text: field(3)) {
        result += decoded.text
        issues.formUnion(decoded.issues)
        previousWasEncoded = true
      } else {
        issues.insert(.invalidEncodedWord)
        result += value[range]
        previousWasEncoded = false
      }
      position = range.upperBound
    }
    return result + unencodedHeader(String(value[position...]), issues: &issues)
  }

  private static func encodedWord(charset: String, encoding: String, text: String)
    -> (text: String, issues: Set<DecodingIssue>)?
  {
    var issues: Set<DecodingIssue> = []
    let bytes =
      encoding.lowercased() == "b"
      ? base64(text, issues: &issues)
      : quotedPrintable(text.replacingOccurrences(of: "_", with: " "), issues: &issues)
    guard issues.isEmpty else { return nil }
    let decoded = decode(bytes, charset: charset, issues: &issues)
    return (decoded, issues)
  }

  /// Interprets byte-preserved raw header text as UTF-8 when it is valid, otherwise as Latin-1.
  private static func unencodedHeader(_ value: String, issues: inout Set<DecodingIssue>) -> String {
    if let text = String(data: Data(latin1Bytes(value)), encoding: .utf8) { return text }
    issues.insert(.invalidCharacters)
    return value
  }

  private static func fallbackText(_ data: Data) -> String {
    String(data: data, encoding: .utf8)
      ?? String(data: data, encoding: .windowsCP1252)
      ?? String(String.UnicodeScalarView(data.map(Unicode.Scalar.init)))
  }

  /// Returns the index after a soft line break, which may carry trailing whitespace.
  private static func softLineBreakEnd(_ bytes: [UInt8], equalsSignAt index: Int) -> Int? {
    var next = index + 1
    while next < bytes.count, bytes[next] == UInt8(ascii: " ") || bytes[next] == UInt8(ascii: "\t")
    {
      next += 1
    }
    if next == bytes.count { return next }
    return bytes[next] == lineFeed ? next + 1 : nil
  }

  static func hexValue(_ byte: UInt8) -> UInt8? {
    switch byte {
      case UInt8(ascii: "0")...UInt8(ascii: "9"): byte - UInt8(ascii: "0")
      case UInt8(ascii: "A")...UInt8(ascii: "F"): byte - UInt8(ascii: "A") + 10
      case UInt8(ascii: "a")...UInt8(ascii: "f"): byte - UInt8(ascii: "a") + 10
      default: nil
    }
  }

  private static func isWhitespace(_ byte: UInt8) -> Bool {
    [UInt8(ascii: " "), UInt8(ascii: "\t"), UInt8(ascii: "\r"), lineFeed].contains(byte)
  }

  /// Recovers the original bytes from the parser's byte-preserving Latin-1 text.
  static func latin1Bytes(_ text: some StringProtocol) -> [UInt8] {
    text.unicodeScalars.map { UInt8(truncatingIfNeeded: $0.value) }
  }
}
