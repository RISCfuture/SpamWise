public import Foundation
import ImageIO

/// ImageIO validation of a message's embedded raster parts, without remote resources.
public struct EmbeddedImages: Sendable {
  private static let maximumTotalImageBytes = 1_048_576
  private static let maximumTotalImagePixels = 8_000_000
  private static let maximumImageDimension = 4096
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

  /// Creates the bounded image validator.
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

  /**
   Returns the raster bytes of supported image parts after ImageIO checks their type and size.

   Parts of other image types are ignored. Fails without decoding any image when there are too
   many supported parts, or when one is invalid or exceeds a byte, dimension or pixel limit.
   */
  public func extract(from images: [InlineImage]) throws -> [Data] {
    let supported = images.filter { Self.imageTypes[$0.mediaType] != nil }
    guard supported.count <= Self.maximumImages else { throw ParseError.tooLarge }
    var validated: [Data] = [], bytes = 0, pixels = 0
    for image in supported {
      guard let data = image.data(maximumBytes: Self.maximumImageBytes) else {
        throw ParseError.tooLarge
      }
      pixels += try Self.pixels(in: data, mime: image.mediaType)
      bytes += data.count
      guard bytes <= Self.maximumTotalImageBytes, pixels <= Self.maximumTotalImagePixels else {
        throw ParseError.tooLarge
      }
      validated.append(data)
    }
    return validated
  }
}
