import Foundation
import Testing
import SpamWiseCore

@Test
func `extracts optional text attachments without interpreting active documents`() throws {
  let source = """
    From: person@example.org
    Content-Type: text/html; charset=utf-8
    Content-Disposition: attachment; filename=invoice.html

    <script>fetch('https://attacker.example')</script><img \
    src="https://attacker.example/pixel"><p>Invoice offer</p>
    """
  let raw = Data(source.utf8)
  #expect(try MIMEParser().parse(raw).text.isEmpty)
  #expect(
    try DocumentInspection(raw: raw, includeTextAttachments: false).coverage.map(\.status)
      == [.omitted]
  )
  let inline = try MIMEParser().parse(
    Data(source.replacingOccurrences(of: "attachment;", with: "inline;").utf8)
  )
  #expect(inline.text == "Invoice offer")
  #expect(inline.urls == ["https://attacker.example/pixel"])
  #expect(inline.attachments?.first?.filename == "invoice.html")
  let extracted = try MIMEParser(includeTextAttachments: true).parse(raw)
  #expect(extracted.text.contains("Invoice offer"))
  #expect(!extracted.text.contains("fetch"))
  let inspected = try DocumentInspection(raw: raw)
  #expect(inspected.message == extracted)
  #expect(inspected.coverage.map(\.status) == [.extracted])
  let oversized = Data((source + String(repeating: "x", count: 66_000)).utf8)
  let unavailable = try DocumentInspection(raw: oversized)
  #expect(unavailable.message.text.isEmpty)
  #expect(unavailable.coverage.map(\.status) == [.unavailable])
  let mixed = Data(
    ("From: person@example.org\nContent-Type: multipart/mixed; boundary=documents\n\n"
      + "--documents\nContent-Type: text/plain\n\nBody evidence\n"
      + "--documents\n" + source + String(repeating: "x", count: 66_000)
      + "\n--documents--\n").utf8
  )
  let preserved = try DocumentInspection(raw: mixed)
  #expect(preserved.message.text.contains("Body evidence"))
  #expect(!preserved.message.text.contains("Invoice offer"))
  #expect(preserved.coverage.map(\.status) == [.unavailable])
  for mediaType in ["application/pdf", "application/vnd.ms-word.document.macroEnabled.12"] {
    let unsupported = Data(source.replacingOccurrences(of: "text/html", with: mediaType).utf8)
    let message = try MIMEParser(includeTextAttachments: true).parse(unsupported)
    #expect(message.text.isEmpty)
    #expect(message.attachments?.first?.mediaType == mediaType.lowercased())
    #expect(try DocumentInspection(raw: unsupported).coverage.map(\.status) == [.unsupported])
  }
  let malformed = Data(
    source.replacingOccurrences(of: "\n\n", with: "\nContent-Transfer-Encoding: base64\n\n").utf8
  )
  let degraded = try DocumentInspection(raw: malformed)
  #expect(degraded.coverage.map(\.status) == [.extracted])
  #expect(degraded.message.decodingIssues?.contains(.invalidBase64) == true)
  let inlinePDF = Data("From: a@example.org\nContent-Type: application/pdf\n\n%PDF-broken".utf8)
  let pdf = try DocumentInspection(raw: inlinePDF)
  #expect(pdf.message.text.isEmpty)
  #expect(pdf.coverage.map(\.status) == [.unsupported])
}

@Test
func `reads RFC 2231 parameters and drops repeated filenames`() throws {
  func filename(_ disposition: String) throws -> (String?, [DecodingIssue]?) {
    let message = try MIMEParser().parse(
      Data(
        ("From: a@example.org\nContent-Type: application/pdf; name=legacy.pdf\n"
          + "Content-Disposition: \(disposition)\n\n%PDF").utf8
      )
    )
    return (message.attachments?.first?.filename, message.decodingIssues)
  }
  for (disposition, name) in [
    ("attachment; filename*=UTF-8''Invoice%20123.html", "Invoice 123.html"),
    ("attachment; filename*0=\"Long \"; filename*1*=%C3%A9t%C3%A9.pdf", "Long été.pdf"),
    ("attachment; filename*1=\"b.pdf\"; filename*0*=utf-8'en'a%20", "a b.pdf"),
    ("attachment; filename=\"semi;colon \\\"q\\\".pdf\"", "semi;colon \"q\".pdf"),
    ("attachment; filename*=utf-8''%E2%9C%93.pdf", "✓.pdf"),
    ("attachment; filename==?utf-8?q?R=C3=A9sum=C3=A9?=.pdf", "Résumé.pdf")
  ] {
    let (decoded, issues) = try filename(disposition)
    #expect(decoded == name)
    #expect(issues == nil)
  }
  for disposition in [
    "attachment; filename=a.pdf; FILENAME=b.pdf",
    "attachment; filename*0=a; filename*0=b",
    "attachment; filename*0=a; filename*2=c",
    "attachment; filename=plain.pdf; filename*=utf-8''%E2%9C%93.pdf"
  ] {
    let (decoded, issues) = try filename(disposition)
    #expect(decoded == nil)
    #expect(issues == [.ambiguousPartHeaders])
  }
}
