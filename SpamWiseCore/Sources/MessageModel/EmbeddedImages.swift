public import Foundation
import ImageIO

/// Bounded extraction of embedded base64 raster MIME parts, without remote resources.
public struct EmbeddedImages: Sendable {
  private static let maximumMessageBytes = 2_000_000
  private static let maximumHeaderBytes = 65_536
  private static let maximumTotalImageBytes = 1_048_576
  private static let maximumTotalImagePixels = 8_000_000
  private static let maximumImageDimension = 4096
  private static let maximumNestingDepth = 12
  private static let maximumParts = 128
  private static let maximumBoundaryCharacters = 200
  private static let imageTypes = [
    "image/png": "public.png", "image/jpeg": "public.jpeg",
    "image/gif": "com.compuserve.gif", "image/tiff": "public.tiff", "image/heic": "public.heic"
  ]
  /// Maximum inline images accepted for one message.
  public static let maximumImages = 4
  /// Maximum decoded bytes in one image.
  public static let maximumImageBytes = 524_288
  /// Maximum decoded pixels in one image.
  public static let maximumImagePixels = 4_000_000

  /// Creates the bounded MIME image extractor.
  public init() {}

  private static func pixels(in data: Data, mime: String) throws -> Int {
    let options = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithData(data as CFData, options),
      CGImageSourceGetCount(source) == 1,
      let type = CGImageSourceGetType(source) as String?,
      type == imageTypes[mime],
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int,
      width > 0, height > 0, width <= Self.maximumImageDimension,
      height <= Self.maximumImageDimension,
      width <= maximumImagePixels / height
    else { throw ParseError.tooLarge }
    return width * height
  }

  /// Extracts validated raster bytes; unsupported or excessive MIME fails without image decoding.
  public func extract(from raw: Data) throws -> [Data] {
    guard raw.count <= Self.maximumMessageBytes else { throw ParseError.tooLarge }
    let source = String(decoding: raw, as: UTF8.self).replacingOccurrences(of: "\r\n", with: "\n")
    var state = Extraction()
    try visit(source, depth: 0, state: &state)
    return state.images
  }

  private func visit(_ source: String, depth: Int, state: inout Extraction) throws {
    state.parts += 1
    guard depth <= Self.maximumNestingDepth, state.parts <= Self.maximumParts else {
      throw ParseError.tooLarge
    }
    let (headers, body) = try split(source)
    let contentType = headers["content-type"] ?? "text/plain"
    let mime = contentType.components(separatedBy: ";")[0].lowercased().trimmingCharacters(
      in: .whitespaces
    )
    if mime.hasPrefix("multipart/") {
      let boundary = try boundary(in: contentType)
      var current: [String]?, closed = false, children = 0
      for line in body.components(separatedBy: "\n") {
        let delimiter = line.trimmingCharacters(in: .whitespaces)
        if delimiter == "--" + boundary || delimiter == "--" + boundary + "--" {
          if let current {
            try visit(current.joined(separator: "\n"), depth: depth + 1, state: &state)
            children += 1
          }
          current = []
          if delimiter == "--" + boundary + "--" { closed = true; break }
        } else if current != nil {
          current?.append(line)
        }
      }
      guard closed, children > 0 else { throw ParseError.malformed }
      return
    }
    guard Self.imageTypes[mime] != nil else { return }
    guard headers["content-transfer-encoding"]?.lowercased() == "base64" else {
      throw ParseError.invalidEncoding
    }
    guard state.images.count < Self.maximumImages else { throw ParseError.tooLarge }
    let compact = body.filter { !$0.isWhitespace }
    guard compact.utf8.count <= ((Self.maximumImageBytes + 2) / 3) * 4,
      let data = Data(base64Encoded: compact), data.count <= Self.maximumImageBytes
    else { throw ParseError.tooLarge }
    let pixels = try Self.pixels(in: data, mime: mime)
    state.bytes += data.count; state.pixels += pixels
    guard state.bytes <= Self.maximumTotalImageBytes, state.pixels <= Self.maximumTotalImagePixels
    else { throw ParseError.tooLarge }
    state.images.append(data)
  }

  private func split(_ source: String) throws -> ([String: String], String) {
    guard let separator = source.range(of: "\n\n"),
      source[..<separator.lowerBound].utf8.count <= Self.maximumHeaderBytes
    else {
      throw ParseError.malformed
    }
    var lines: [String] = []
    for line in source[..<separator.lowerBound].components(separatedBy: "\n") {
      if line.first == " " || line.first == "\t" {
        guard !lines.isEmpty else { throw ParseError.malformed }
        lines[lines.count - 1] += " " + line.trimmingCharacters(in: .whitespaces)
      } else {
        lines.append(line)
      }
    }
    var headers: [String: String] = [:]
    for line in lines {
      guard let colon = line.firstIndex(of: ":") else { throw ParseError.malformed }
      let key = String(line[..<colon]).lowercased()
      guard ["content-type", "content-transfer-encoding", "content-disposition"].contains(key)
      else { continue }
      guard headers[key] == nil else { throw ParseError.malformed }
      headers[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
    }
    return (headers, String(source[separator.upperBound...]))
  }

  private func boundary(in contentType: String) throws -> String {
    let expression = try NSRegularExpression(
      pattern: #"(?:^|;)\s*boundary\s*=\s*(?:"([^"]*)"|([^;\s]+))"#,
      options: .caseInsensitive
    )
    let matches = expression.matches(
      in: contentType,
      range: NSRange(contentType.startIndex..., in: contentType)
    )
    guard matches.count == 1, let match = matches.first else { throw ParseError.malformed }
    let range = match.range(at: 1).location == NSNotFound ? match.range(at: 2) : match.range(at: 1)
    guard let range = Range(range, in: contentType) else { throw ParseError.malformed }
    let value = String(contentType[range])
    guard !value.isEmpty, value.count <= Self.maximumBoundaryCharacters else {
      throw ParseError.malformed
    }
    return value
  }

  private struct Extraction {
    var parts = 0
    var bytes = 0
    var pixels = 0
    var images: [Data] = []
  }
}
