import Foundation
import Testing
import SpamWiseCore

private let pixelPNG =
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a4y8AAAAASUVORK5CYII="

private func imageMessage(
  parts: Int = 1,
  payload: String = pixelPNG,
  attachment: Bool = false,
  mime: String = "image/png"
)
  -> Data
{
  let disposition = attachment ? "attachment" : "inline"
  let image = """
    --images
    Content-Type: \(mime)
    Content-Disposition: \(disposition)
    Content-Transfer-Encoding: base64

    \(payload)

    """
  return Data(
    ("From: sender@example.org\nContent-Type: multipart/related; boundary=images\n\n"
      + Array(repeating: image, count: parts).joined() + "--images--\n").utf8
  )
}

extension EmbeddedImageOCR {
  /// Parses a raw message and recognizes text in its embedded images.
  fileprivate func text(from raw: Data) async -> String? {
    guard let inspection = try? DocumentInspection(raw: raw) else { return nil }
    return await text(from: inspection.images)
  }
}

@Test func `recognizes text only from bounded embedded image bytes`() async throws {
  let ocr = EmbeddedImageOCR { data in
    #expect(data == Data(base64Encoded: pixelPNG))
    return "Offer shown inside image"
  }
  #expect(await ocr.text(from: imageMessage()) == "Offer shown inside image")
  #expect(await ocr.text(from: imageMessage(attachment: true)) == "Offer shown inside image")
  let gif = "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"
  let additional = EmbeddedImageOCR { _ in "Static image text" }
  #expect(
    await additional.text(from: imageMessage(payload: gif, mime: "image/gif"))
      == "Static image text"
  )
  #expect(await additional.text(from: imageMessage(payload: gif, mime: "image/png")) == nil)
  #expect(await ocr.text(from: imageMessage(parts: 5)) == nil)
  #expect(await ocr.text(from: imageMessage(payload: "invalid")) == nil)
  let remote = Data(
    "From: a@example.org\nContent-Type: text/html\n\n<img src=\"https://example.com/pixel.png\">"
      .utf8
  )
  #expect(await ocr.text(from: remote) == nil)
  let verbose = EmbeddedImageOCR { _ in String(repeating: "x", count: 1000) }
  let text = try #require(await verbose.text(from: imageMessage(parts: 4)))
  #expect(text.count <= 3000)
}

@Test func `rejects oversized image payloads and dimensions before recognition`()
  async throws
{
  let ocr = EmbeddedImageOCR { _ in
    Issue.record("Oversized images must not reach Vision")
    return "unexpected"
  }
  #expect(await ocr.text(from: Data(repeating: 0, count: 2_000_001)) == nil)
  #expect(
    await ocr.text(
      from: imageMessage(payload: Data(repeating: 0, count: 524_289).base64EncodedString())
    ) == nil
  )
  var huge = try #require(Data(base64Encoded: pixelPNG))
  huge.replaceSubrange(16..<24, with: [0, 1, 0, 0, 0, 1, 0, 0])
  #expect(await ocr.text(from: imageMessage(payload: huge.base64EncodedString())) == nil)
}
