public import Foundation
import ImageIO

/**
 ImageIO validation of a message's embedded PNG and JPEG parts, without remote resources.

 A part reaches ImageIO only when its bytes begin with the signature of its declared format, and
 ImageIO must then identify that same format, so other formats' decoders never parse unopened
 mail.
 */
public struct EmbeddedImages: Sendable {
  private static let maximumTotalImageBytes = 1_048_576
  private static let maximumTotalImagePixels = 8_000_000
  private static let maximumImageDimension = 4096
  private static let formats = [
    "image/png": ImageFormat(
      typeIdentifier: "public.png",
      signature: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    ),
    "image/jpeg": ImageFormat(typeIdentifier: "public.jpeg", signature: [0xFF, 0xD8, 0xFF])
  ]
  /// Maximum inline images accepted for one message.
  public static let maximumImages = 4
  /// Maximum decoded bytes in one image.
  public static let maximumImageBytes = 524_288
  /// Maximum decoded pixels in one image.
  public static let maximumImagePixels = 4_000_000

  /// Creates the bounded image validator.
  public init() {}

  private static func pixels(in data: Data, format: ImageFormat) throws -> Int {
    guard data.starts(with: format.signature) else { throw ParseError.tooLarge }
    let options =
      [
        kCGImageSourceShouldCache: false,
        kCGImageSourceTypeIdentifierHint: format.typeIdentifier as CFString
      ] as CFDictionary
    guard let source = CGImageSourceCreateWithData(data as CFData, options),
      CGImageSourceGetCount(source) == 1,
      let type = CGImageSourceGetType(source) as String?,
      type == format.typeIdentifier,
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int,
      width > 0, height > 0, width <= Self.maximumImageDimension,
      height <= Self.maximumImageDimension,
      width <= maximumImagePixels / height
    else { throw ParseError.tooLarge }
    return width * height
  }

  /**
   Returns the raster bytes of supported image parts after ImageIO checks their type and size.

   Parts of other image types are ignored. Fails without decoding any image when there are too
   many supported parts, or when one is invalid or exceeds a byte, dimension or pixel limit.
   */
  public func extract(from images: [InlineImage]) throws -> [Data] {
    let supported = images.compactMap { image in
      Self.formats[image.mediaType].map { (image, $0) }
    }
    guard supported.count <= Self.maximumImages else { throw ParseError.tooLarge }
    var validated: [Data] = [], bytes = 0, pixels = 0
    for (image, format) in supported {
      guard let data = image.data(maximumBytes: Self.maximumImageBytes) else {
        throw ParseError.tooLarge
      }
      pixels += try Self.pixels(in: data, format: format)
      bytes += data.count
      guard bytes <= Self.maximumTotalImageBytes, pixels <= Self.maximumTotalImagePixels else {
        throw ParseError.tooLarge
      }
      validated.append(data)
    }
    return validated
  }

  /// A supported raster format, identified by its leading bytes and ImageIO type.
  private struct ImageFormat: Sendable {
    let typeIdentifier: String
    let signature: [UInt8]
  }
}
