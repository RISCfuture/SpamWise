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
