import Foundation
import Testing
import SpamWiseCore
func fixture(_ name: String) throws -> Data {
    try Data(contentsOf: #require(Bundle.module.url(forResource: name, withExtension: "eml", subdirectory: "Fixtures")))
}
@Test(arguments: ["filler-spam", "stranger-cart", "unsolicited-newsletter", "order-confirmation", "personal"])
func requiredFixtures(_ name: String) throws {
    let message = try MIMEParser().parse(fixture(name))
    #expect(!message.subject.isEmpty)
    #expect(!message.text.isEmpty)
    #expect(message.fromAddress.contains("@"))
}
@Test func decodesMIMEAndFoldedHeaders() throws {
    let message = try MIMEParser().parse(fixture("encoded"))
    #expect(message.subject == "Café with lunch")
    #expect(message.fromDisplayName == "José")
    #expect(message.text.contains("Café"))
    #expect(message.urls.contains("https://shop.example.co.uk/order"))
}
@Test func malformedFailsOpen() throws {
    #expect(throws: (any Error).self) { try MIMEParser().parse(fixture("malformed")) }
    #expect(throws: (any Error).self) { try MIMEParser().parse(Data("not mail".utf8)) }
    #expect(throws: (any Error).self) { try MIMEParser().parse(Data(repeating: 65, count: 2_100_000)) }
}
@Test func publicSuffixBoundaries() {
    let domains = DomainResolver()
    #expect(domains.registrableDomain("mail.shop.example.co.uk") == "example.co.uk")
    #expect(domains.registrableDomain("a.user.github.io") == "user.github.io")
    #expect(domains.registrableDomain("co.uk") == nil)
    #expect(domains.registrableDomain("www.city.kawasaki.jp") == "city.kawasaki.jp")
    #expect(domains.registrableDomain("127.0.0.1") == nil)
}
@Test func htmlNeverIncludesScriptsOrRemoteImages() throws {
    let raw = "From: a@example.com\nContent-Type: text/html\n\n<script>hidden()</script><p>Hello &amp; welcome</p><img src='https://track.example/pixel'><a href='https://example.org'>Link</a>"
    let message = try MIMEParser().parse(Data(raw.utf8))
    #expect(!message.text.contains("hidden"))
    #expect(message.text.contains("Hello & welcome"))
    #expect(message.urls.contains("https://example.org"))
}
