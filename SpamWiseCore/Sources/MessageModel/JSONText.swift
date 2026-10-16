public import Foundation

extension JSONEncoder {
  /**
   Encodes `value` as JSON text.

   - Parameter value: The value to encode.
   - Returns: The UTF-8 JSON text.
   - Throws: `EncodingError` when `value` can’t be encoded or the encoded bytes aren’t UTF-8.
   */
  public func encodeText(_ value: some Encodable) throws -> String {
    let data = try encode(value)
    guard let text = String(data: data, encoding: .utf8) else {
      throw EncodingError.invalidValue(
        value,
        .init(codingPath: [], debugDescription: "The encoded JSON isn’t UTF-8.")
      )
    }
    return text
  }
}
