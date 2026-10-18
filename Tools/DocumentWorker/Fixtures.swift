import CoreText
import Foundation
import PDFKit

enum DocumentFixtures {
  static func pdf(pages: Int = 1, text: String = "Synthetic offer", active: Bool = false) -> Data {
    let action = active ? " /OpenAction << /S /JavaScript /JS (app.alert('synthetic')) >>" : ""
    let children = (0..<pages).map { "\(4 + $0 * 2) 0 R" }.joined(separator: " ")
    var objects = [
      "<< /Type /Catalog /Pages 2 0 R\(action) >>",
      "<< /Type /Pages /Kids [\(children)] /Count \(pages) >>",
      "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"
    ]
    for index in 0..<pages {
      objects.append(
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] "
          + "/Resources << /Font << /F1 3 0 R >> >> /Contents \(5 + index * 2) 0 R >>"
      )
      let fontSize = text.count > 100 ? "0.1" : "12"
      let stream = "BT /F1 \(fontSize) Tf 36 750 Td (\(text)) Tj ET"
      objects.append("<< /Length \(stream.utf8.count) >>\nstream\n\(stream)\nendstream")
    }
    var output = "%PDF-1.7\n", offsets: [Int] = []
    for (index, object) in objects.enumerated() {
      offsets.append(output.utf8.count)
      output += "\(index + 1) 0 obj\n\(object)\nendobj\n"
    }
    let start = output.utf8.count
    output += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
    for offset in offsets {
      let digits = String(offset)
      output += String(repeating: "0", count: 10 - digits.count) + digits + " 00000 n \n"
    }
    output += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(start)\n%%EOF\n"
    return Data(output.utf8)
  }

  /// Typesets Unicode text with system font fallback, so PDFKit extracts the original scalars.
  static func typeset(_ text: String, fontSize: CGFloat = 3) throws -> Data {
    var page = CGRect(x: 0, y: 0, width: 612, height: 792)
    let output = NSMutableData()
    guard let consumer = CGDataConsumer(data: output),
      let context = unsafe CGContext(consumer: consumer, mediaBox: &page, nil)
    else { throw ProbeError.fixture }
    let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
    let bounds = CGMutablePath()
    bounds.addRect(page.insetBy(dx: 18, dy: 18))
    let framesetter = CTFramesetterCreateWithAttributedString(
      NSAttributedString(string: text, attributes: [.font: font])
    )
    let frame = CTFramesetterCreateFrame(
      framesetter,
      CFRange(location: 0, length: 0),
      bounds,
      nil
    )
    context.beginPDFPage(nil)
    CTFrameDraw(frame, context)
    context.endPDFPage()
    context.closePDF()
    return output as Data
  }

  static func encrypted(password: String) throws -> Data {
    guard let document = PDFDocument(data: pdf()),
      let data = document.dataRepresentation(options: [
        PDFDocumentWriteOption.ownerPasswordOption: "synthetic-owner",
        PDFDocumentWriteOption.userPasswordOption: password
      ])
    else { throw ProbeError.fixture }
    return data
  }
}

enum ProbeError: Error { case fixture, failed(String) }
