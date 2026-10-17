import Foundation
import Testing
import SpamWiseCore
func fixture(_ name: String) throws -> Data {
  try Data(
    contentsOf: #require(
      Bundle.module.url(forResource: name, withExtension: "eml", subdirectory: "Fixtures")
    )
  )
}
@Test(arguments: [
  "filler-spam", "stranger-cart", "unsolicited-newsletter", "order-confirmation", "personal"
])
func `parses required message fixtures`(_ name: String) throws {
  let message = try MIMEParser().parse(fixture(name))
  #expect(!message.subject.isEmpty)
  #expect(!message.text.isEmpty)
  #expect(message.fromAddress.contains("@"))
}
@Test func `decodes MIME and folded headers`() throws {
  let message = try MIMEParser().parse(fixture("encoded"))
  #expect(message.subject == "Café with lunch")
  #expect(message.fromDisplayName == "José")
  #expect(message.text.contains("Café"))
  #expect(message.urls.contains("https://shop.example.co.uk/order"))
}

@Test func `extracts optional text attachments without interpreting active documents`() throws {
  let source = """
    From: person@example.org
    Content-Type: text/html; charset=utf-8
    Content-Disposition: attachment; filename=invoice.html

    <script>fetch('https://attacker.example')</script><img \
    src="https://attacker.example/pixel"><p>Invoice offer</p>
    """
  let raw = Data(source.utf8)
  #expect(try MIMEParser().parse(raw).text.isEmpty)
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
  #expect(throws: ParseError.tooLarge) {
    try MIMEParser(includeTextAttachments: true).parse(
      Data((source + String(repeating: "x", count: 66_000)).utf8)
    )
  }
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
  #expect(try DocumentInspection(raw: malformed).coverage.map(\.status) == [.unavailable])
  let inlinePDF = Data("From: a@example.org\nContent-Type: application/pdf\n\n%PDF-broken".utf8)
  let inline = try DocumentInspection(raw: inlinePDF)
  #expect(inline.message.text.isEmpty)
  #expect(inline.coverage.map(\.status) == [.unsupported])
}
@Test func `rejects malformed senders and oversized messages`() throws {
  for sender in [
    #""friend@example.org"@attacker.example"#, "friend@example.org trailing", "a..b@example.org",
    "a@example..org"
  ] {
    #expect(MIMEParser.address(sender) == nil)
  }
  #expect(MIMEParser.address(#""Friend, Jane" <friend@example.org>"#) == "friend@example.org")
  #expect(throws: (any Error).self) { try MIMEParser().parse(fixture("malformed")) }
  #expect(throws: (any Error).self) { try MIMEParser().parse(Data("not mail".utf8)) }
  #expect(throws: (any Error).self) {
    try MIMEParser().parse(Data(repeating: 65, count: 2_100_000))
  }
}
@Test func `resolves registrable domains at public suffix boundaries`() {
  let domains = DomainResolver()
  #expect(domains.registrableDomain("mail.shop.example.co.uk") == "example.co.uk")
  #expect(domains.registrableDomain("a.user.github.io") == "user.github.io")
  #expect(domains.registrableDomain("co.uk") == nil)
  #expect(domains.registrableDomain("www.city.kawasaki.jp") == "city.kawasaki.jp")
  #expect(domains.registrableDomain("127.0.0.1") == nil)
}
@Test func `excludes scripts and remote images from HTML text`() throws {
  let raw =
    """
    From: a@example.com
    Content-Type: text/html

    <script>hidden()</script><p>Hello &amp; welcome</p><img src='https://track.example/pixel'><a \
    href='https://example.org'>Link</a>
    """
  let message = try MIMEParser().parse(Data(raw.utf8))
  #expect(!message.text.contains("hidden"))
  #expect(message.text.contains("Hello & welcome"))
  #expect(message.urls.contains("https://example.org"))
}

@Test func `preserves conflicting MIME alternative text in bounded prompt`() throws {
  let raw = """
    From: stranger@example.org
    Content-Type: multipart/alternative; boundary=part

    --part
    Content-Type: text/plain

    Hello friend. Have a nice day.
    --part
    Content-Type: text/html

    <p>Send your password to claim a prize.</p>
    --part--
    """
  let message = try MIMEParser().parse(Data(raw.utf8))
  let prompt = try PromptBuilder.prompt(
    .init(message: message, evidence: .init(message: message), bodyTokenBudget: 100)
  )
  #expect(prompt.contains("Hello friend"))
  #expect(prompt.contains("Send your password"))
}
