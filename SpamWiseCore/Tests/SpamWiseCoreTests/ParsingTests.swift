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
/// Parses mail from its source text.
private func parsed(_ source: String) throws -> ParsedMessage {
  try MIMEParser().parse(Data(source.utf8))
}

/// Parses an HTML body sent from a fixed sender.
private func parsedHTML(_ html: String) throws -> ParsedMessage {
  try parsed("From: a@example.com\nContent-Type: text/html\n\n" + html)
}

@Test
func `decodes encoded words and folded headers`() throws {
  let message = try MIMEParser().parse(fixture("encoded"))
  #expect(message.subject == "Café with lunch")
  #expect(message.fromDisplayName == "José")
  #expect(message.text.contains("Café"))
  #expect(message.urls.contains("https://shop.example.co.uk/order"))
  #expect(message.decodingIssues == nil)
}

@Test
func `keeps the readable text of degraded parts and records each issue`() throws {
  let degraded = try MIMEParser().parse(degradedMessage())
  #expect(degraded.subject == "=?utf-8?B?***?= Cheap meds")
  for text in [
    "Don\u{FFFD}t miss", "Café", "Prix 50€", "50% off = todaynow =ZZ end", "Hello world",
    "Headerless body", "Unreadable header line", "Ambiguous charset", "Hi there", "Buy cheap meds"
  ] {
    #expect(degraded.text.contains(text))
  }
  #expect(!degraded.text.contains("QnV5"))
  #expect(
    degraded.decodingIssues == [
      .invalidCharacters, .unknownCharset, .invalidQuotedPrintable, .invalidBase64,
      .invalidEncodedWord, .unknownTransferEncoding, .malformedPartHeaders
    ]
  )
}

@Test
func `reads mail with structural quirks and records each issue`() throws {
  for structure in try structuralMessages() {
    let message = try parsed(structure.source)
    #expect(message.text.trimmingCharacters(in: .whitespacesAndNewlines) == structure.text)
    #expect(message.decodingIssues == structure.issues)
  }
}

@Test(arguments: [
  "From: a@example.org\nContent-Type: multipart/mixed; boundary=\"a\"; boundary=\"b\"\n\n"
    + "--a\n\nSafe\n--a--\n",
  "From: a@example.org\nContent-Type: multipart/mixed; boundary=a; Boundary*=''b\n\n"
    + "--a\n\nSafe\n--a--\n",
  "From: a@example.org\nContent-Type: text/plain\n"
    + "Content-Type : multipart/alternative; boundary=b\n\n--b\n\nHi\n--b--\n"
])
func `conceals the body of mail with ambiguous part headers`(_ source: String) throws {
  let message = try parsed(source)
  #expect(message.text.isEmpty)
  #expect(message.decodingIssues == [.ambiguousPartHeaders])
  #expect(message.concealsContent)
}

@Test
func `reads a Latin-1 subject and records its invalid characters`() throws {
  let latin1Subject = try MIMEParser().parse(
    Data(Array("From: a@example.org\nSubject: Caf".utf8) + [0xE9] + Array("\n\nBody".utf8))
  )
  #expect(latin1Subject.subject == "Café")
  #expect(latin1Subject.decodingIssues == [.invalidCharacters])
}

@Test
func `tells the classifier that decoding degraded`() async throws {
  let pipeline = Pipeline(
    store: try testStore(),
    classifier: MockClassifier(operation: { input in
      #expect(
        input.evidence.auxiliaryFindings?.first?.hasPrefix("Message decoding degraded") == true
      )
      return .init(label: .review, confidence: 50, reason: "Garbled text")
    })
  )
  let raw = try degradedMessage()
  let record = await pipeline.process(
    MailEnvelope(identity: .init(accountID: "account-A", contentHash: stableHash(raw)), raw: raw)
  )
  #expect(record.path == .model)
}

@Test
func `sends mail over the part limit to Review as concealed content`() async throws {
  let concealing = Data(
    ("From: a@example.org\nContent-Type: multipart/mixed; boundary=b\n\n"
      + String(repeating: "--b\n\nPart\n", count: 130) + "--b--\n").utf8
  )
  #expect(try MIMEParser().parse(concealing).decodingIssues == [.partLimitExceeded])
  let flagged = await Pipeline(
    store: try testStore(),
    classifier: MockClassifier(verdict: .init(label: .inbox, confidence: 90, reason: "Fine"))
  ).process(
    MailEnvelope(
      identity: .init(accountID: "account-A", contentHash: stableHash(concealing)),
      raw: concealing
    )
  )
  #expect(flagged.decision.label == .review)
  #expect(flagged.decision.reason == .concealedContent)
}

/// Messages with tolerated structural quirks, their trimmed body text and recorded issues.
private struct StructuralMessage {
  var source: String, text: String, issues: [DecodingIssue]?
}

private func structuralMessages() throws -> [StructuralMessage] {
  [
    .init(
      source: "From: a@example.org\nContent-Type: multipart/alternative; boundary=b\n\n--b\n"
        + "Content-Type: text/plain; charset=utf-8\n--b\nContent-Type: text/html\n\n"
        + "<p>Hello</p>\n--b--\n",
      text: "Hello",
      issues: nil
    ),
    .init(source: "From: a@example.org\nSubject: Headers only", text: "", issues: nil),
    .init(
      source: try #require(String(data: fixture("malformed"), encoding: .utf8)),
      text: "unterminated",
      issues: [.incompleteMultipart]
    ),
    .init(
      source: "From: a@example.org\nContent-Type: multipart/mixed; boundary=b\n\nNo parts",
      text: "No parts",
      issues: [.incompleteMultipart]
    ),
    .init(
      source: "From: a@example.org\nContent-Type: multipart/mixed; boundary=b\n\n--b--\n--b\n"
        + "Content-Type: text/html\n\n<p>Pitch after close</p>\n--b--\n",
      text: "Pitch after close",
      issues: [.incompleteMultipart]
    ),
    .init(
      source: " leading fold\nNo colon\nFrom: a@example.org\n\nBody",
      text: "Body",
      issues: [.malformedMessageHeaders]
    ),
    .init(
      source: "From: a@example.org\nContent-Type: multipart/mixed; boundary=b\n\n--b\n\nBody\n--b\n"
        + "Content-Type: application/\(String(repeating: "x", count: 300))\n\n%PDF\n--b--\n",
      text: "Body",
      issues: nil
    ),
    .init(
      source: "From: a@example.org\nContent-Type: multipart/mixed; boundary=\"\"\n\nEmpty boundary",
      text: "Empty boundary",
      issues: [.invalidMultipartBoundary]
    ),
    .init(
      source: "From: a@example.org\nContent-Type: multipart/mixed; boundary=b\n\n--b\n"
        + "Content-Type: multipart/alternative\n\nMissing boundary\n--b\n"
        + "Content-Type: text/plain\nContent-Type: text/html\n\nAmbiguous\n--b--\n",
      text: "Missing boundary",
      issues: [.ambiguousPartHeaders, .invalidMultipartBoundary]
    ),
    .init(
      source: "From: a@example.org\nContent-Type: multipart/mixed; boundary=b\n\n--b\n\nBody\n--b\n"
        + "Content-Type: multipart/alternative; boundary=x; boundary=y\n\n--x\n\nHidden\n--x--\n"
        + "--b--\n",
      text: "Body",
      issues: [.ambiguousPartHeaders]
    )
  ]
}

private func degradedMessage() throws -> Data {
  let parts: [(headers: String, body: [UInt8])] = [
    ("Content-Type: text/plain; charset=utf-8", Array("Don".utf8) + [0x92] + Array("t miss".utf8)),
    ("Content-Type: text/plain; charset=us-ascii", Array("Caf".utf8) + [0xE9]),
    ("Content-Type: text/plain; charset=x-unknown", Array("Prix 50".utf8) + [0x80]),
    (
      "Content-Type: text/plain\nContent-Transfer-Encoding: quoted-printable",
      Array("50% off = today=\nnow =ZZ end= \n".utf8)
    ),
    ("Content-Type: text/plain\nContent-Transfer-Encoding: base64", Array("SGVsbG8gd29ybGQ".utf8)),
    ("Content-Type: text/plain\nContent-Transfer-Encoding: base64", Array("SGk=IHRoZXJl".utf8)),
    ("Content-Type: text/plain\nContent-Transfer-Encoding: x-custom", Array("Custom".utf8)),
    ("", Array("Headerless body".utf8)),
    ("Content-Type: text/plain; charset=utf-8; charset=koi8-r", Array("Ambiguous charset".utf8)),
    ("Unreadable header line", Array("More".utf8)),
    ("Content-Transfer-Encoding: base64\nBad header line", Array("QnV5IGNoZWFwIG1lZHM=".utf8))
  ]
  var raw = Array(
    """
    From: sender@example.org
    Subject: =?utf-8?B?***?= Cheap meds
    Content-Type: multipart/mixed; boundary=b


    """.utf8
  )
  for part in parts { raw += Array("--b\n\(part.headers)\n\n".utf8) + part.body + [0x0A] }
  return Data(raw + Array("--b--\n".utf8))
}

@Test(arguments: [
  #""friend@example.org"@attacker.example"#, "friend@example.org trailing", "a..b@example.org",
  "a@example..org", "a@example.org, b@example.org", "Jane <a@example.org> <b@example.org>",
  "Jane <a@example.org> trailing", #""Unterminated <a@example.org>"#
])
func `reads no address from a malformed sender`(_ sender: String) {
  #expect(MIMEParser.address(sender) == nil)
}

@Test(arguments: [
  "From: \"friend@example.org\"@attacker.example", "From: PayPal <alerts@evil.top>>",
  "From: \"service@paypal.com <alerts@evil.top>", "From: <alerts@evil.top (x)>",
  "From: Doe, Jane <jane@example.org>", "From: friend@example.org\nFrom: evil@attacker.top",
  "From: friend@example.org\nFrom : evil@attacker.top", "Subject: No sender"
])
func `refuses mail whose sender can't be read`(_ headers: String) {
  #expect(throws: ParseError.unreadableSender) { try parsed("\(headers)\n\nVerify now.") }
}

@Test
func `reads quoted display names and the first address of a sender list`() throws {
  #expect(MIMEParser.address(#""Friend, Jane" <friend@example.org>"#) == "friend@example.org")
  for sender in [#""PayPal" <x@evil.top>,"#, ", (empty) ,x@evil.top"] {
    #expect(try parsed("From: \(sender)\n\nVerify now.").fromAddress == "x@evil.top")
  }
  #expect(
    Mailbox.list(#""Doe, Jane" <jane@example.org>, bob@example.org (Bob), not an address"#)
      .map(\.address) == ["jane@example.org", "bob@example.org"]
  )
}

@Test
func `reads the display name and address of a sender with comments`() throws {
  let spoof = try parsed(
    #"""
    From: "service@paypal.com" (Customer \(Care\)) <Alerts@paypa1-secure.top> (Notice)
    Subject: Account locked

    Verify now.
    """#
  )
  #expect(spoof.fromAddress == "alerts@paypa1-secure.top")
  #expect(spoof.fromDisplayName == "service@paypal.com")
  #expect(EvidenceBundle(message: spoof).mismatchedDisplayNameAddress == "service@paypal.com")
}

@Test(arguments: [
  #""PayPal" (service@paypal.com) <alerts@paypa1-secure.top>"#,
  "PayPal <alerts@paypa1-secure.top> (service@paypal.com)",
  "PayPal (=?utf-8?q?service=40paypal.com?=) <alerts@paypa1-secure.top>"
])
func `keeps a display name apart from the comments around it`(_ sender: String) throws {
  #expect(try parsed("From: \(sender)\n\nVerify now.").fromDisplayName == "PayPal")
}

@Test(arguments: [
  #""Contact service@paypal.com." <alerts@paypa1-secure.top>"#,
  #""Contact service@paypal.com!" <alerts@paypa1-secure.top>"#,
  #""-service@paypal.com?" <alerts@paypa1-secure.top>"#,
  "\"service\u{FF20}paypal.com\" <alerts@paypa1-secure.top>",
  #""PayPal" (service@paypal.com) <alerts@paypa1-secure.top>"#,
  "PayPal <alerts@paypa1-secure.top> (service@paypal.com)",
  "PayPal (=?utf-8?q?service=40paypal.com?=) <alerts@paypa1-secure.top>"
])
func `finds another address in punctuated or commented display names`(_ sender: String) throws {
  let message = try parsed("From: \(sender)\n\nVerify now.")
  #expect(EvidenceBundle(message: message).mismatchedDisplayNameAddress == "service@paypal.com")
}

@Test
func `keeps accented and non-Latin display names`() throws {
  let accented = try parsed("From: Voilà Åsa 株式会社 <shop@example.fr>\n\nBonjour")
  #expect(accented.fromDisplayName == "Voilà Åsa 株式会社")
}

@Test(arguments: [
  #""jane@example.org" <jane@example.org>"#, "jane@example.org (Jane)",
  #""support@github.com" <noreply@github.com>"#
])
func `ignores display names that match the sender`(_ sender: String) throws {
  let matching = try parsed("From: \(sender)\n\nHello")
  #expect(EvidenceBundle(message: matching).mismatchedDisplayNameAddress == nil)
}

@Test
func `rejects text that isn't mail and messages over the size limit`() {
  #expect(throws: (any Error).self) { try parsed("not mail") }
  #expect(throws: (any Error).self) {
    try MIMEParser().parse(Data(repeating: 65, count: 2_100_000))
  }
}

@Test
func `resolves registrable domains at public suffix boundaries`() throws {
  let domains = DomainResolver()
  #expect(domains.registrableDomain("mail.shop.example.co.uk") == "example.co.uk")
  #expect(domains.registrableDomain("a.user.github.io") == "user.github.io")
  #expect(domains.registrableDomain("co.uk") == nil)
  #expect(domains.registrableDomain("www.city.kawasaki.jp") == "city.kawasaki.jp")
  #expect(domains.registrableDomain("127.0.0.1") == nil)
  #expect(domains.registrableDomain("xn--55qx5d.cn") == nil)
  #expect(domains.registrableDomain("shop.xn--55qx5d.cn") == "shop.xn--55qx5d.cn")
  #expect(domains.registrableDomain("mail.shop.公司.cn") == "shop.xn--55qx5d.cn")
  #expect(domains.registrableDomain("WWW.BÜCHER.de") == "xn--bcher-kva.de")
  #expect(try RuleManagement.normalized("Bücher.de", scope: .domain) == "xn--bcher-kva.de")
  #expect(throws: RuleManagementError.invalidRule) {
    try RuleManagement.normalized("公司.cn", scope: .domain)
  }
}
@Test
func `excludes scripts from HTML text and keeps link targets`() throws {
  let message = try parsedHTML(
    "<script>hidden()</script><p>Hello &amp; welcome</p><img src='https://track.example/pixel'>"
      + "<a href='https://example.org'>Link</a>"
  )
  #expect(!message.text.contains("hidden"))
  #expect(message.text.contains("Hello & welcome"))
  #expect(message.urls == ["https://example.org", "https://track.example/pixel"])
}

@Test
func `reads link targets the way browsers decode them`() throws {
  let obscured = try parsedHTML(
    "<!-- https://a.example https://b.example --><p>See zz.example: https://zz.example/x.</p>"
      + "<a href=\"https&#58;//payload.top/login\">a</a><a href=' //relative.top/p '>b</a>"
      + "<a href=\"https:\\\\back.top\\x\">c</a><a href=\"ht&#x74;ps&colon;&sol;&sol;split\n.top\">d</a>"
      + "<a href=\"https://zz.example/x\">again</a><a href=\"mailto:x@y.z\">m</a>"
  )
  #expect(
    obscured.urls == [
      "https://zz.example/x", "https://payload.top/login", "https://relative.top/p",
      "https://back.top/x", "https://split.top"
    ]
  )
}

@Test
func `drops skipped elements and decodes entities in HTML text`() throws {
  let markup = try parsedHTML(
    "<HEAD><title>hidden</title></HEAD><style>p{}</style><!-- hidden -->a < b<br>"
      + "&lt;b&gt;&#x41;&#66;&amp;lt; &bogus; <scriptx>shown</scriptx>"
      + #"<a href="x>y" title='a>b'>link</a>"#
  )
  #expect(markup.text == "a < b\n<b>AB&lt; &bogus; shown link")
}

@Test(arguments: [
  ("<html><head><title>T</title><body><p>Buy cheap meds now</p>", "Buy cheap meds now"),
  ("<html><head/><body>Legit newsletter body</body>", "Legit newsletter body"),
  ("<!-->Empty comment <!--->closes", "Empty comment closes"),
  ("<!-- x --!>Bang-closed comment", "Bang-closed comment"),
  (#"<x="><p>Buy cheap meds now<img alt="">tail"#, "Buy cheap meds now tail"),
  (#"<p =">Buy cheap meds now <b title="">tail"#, "Buy cheap meds now tail"),
  (#"<!x="> Buy cheap meds now <b title="">tail"#, "Buy cheap meds now tail"),
  ("<script=x>Shown text</script=x>", "Shown text")
])
func `keeps the text browsers show after unusual markup`(html: String, visible: String) throws {
  #expect(try parsedHTML(html).text.contains(visible))
}

@Test
func `keeps the text after a long comment`() throws {
  let html = "<!--" + String(repeating: "x", count: 400_000) + "-->Padded text"
  #expect(try parsedHTML(html).text.contains("Padded text"))
}

@Test(
  .serialized,
  arguments: [
    ("", "<!--", 475_000), ("", "<a", 950_000), ("", "<a b=\"", 330_000),
    ("", "<a b='", 330_000), ("<!--", "-", 1_900_000), ("<script>", "</scriptx", 210_000),
    ("<script>", "</script ", 210_000)
  ]
)
func `converts adversarial markup without backtracking`(
  prefix: String,
  repeated: String,
  count: Int
) throws {
  let flood = prefix + String(repeating: repeated, count: count)
  let elapsed = try ContinuousClock().measure { _ = try parsedHTML(flood) }
  #expect(elapsed < .seconds(60))
}

@Test
func `ranks visible links first and moves concealed text after the visible text`() throws {
  let html = """
    <div style="display: none"><a href="https://decoy1.example">x</a> hidden instructions<br></div>
    <span hidden>https://decoy2.example</span><p style="font-size:0px !important">tiny \
    https://decoy3.example</p><a aria-hidden="TRUE" href="https://decoy4.example">gone</a>
    <img src="https://images.example/pixel.png" width="1"><table><tr><td width="0">zero</td>
    </tr></table><a href="https://listed.example/login">Sign in</a> at https://text.example
    <span style="visibility:hidden;color:red">vanished</span> <b style="opacity:0.5">half</b>
    """
  let message = try parsedHTML(html)
  #expect(
    message.urls == [
      "https://listed.example/login", "https://text.example", "https://images.example/pixel.png",
      "https://decoy1.example", "https://decoy2.example", "https://decoy3.example",
      "https://decoy4.example"
    ]
  )
  let parts = message.text.components(separatedBy: "Text the HTML conceals from view:\n")
  #expect(parts.count == 2)
  #expect(parts[0].contains("Sign in at https://text.example"))
  for visible in ["half", "gone"] { #expect(parts[0].contains(visible)) }
  for concealed in ["hidden instructions", "tiny", "zero", "vanished"] {
    #expect(!parts[0].contains(concealed))
    #expect(parts[1].contains(concealed))
  }
}

@Test
func `keeps text visible where a descendant restores its font size, colour or visibility`() throws {
  let html = """
    <table><tr><td style="font-size:0px;text-align:center"><!--[if mso]><table><![endif]-->
    <div class="mj-column" style="font-size:13px;display:inline-block"><a \
    href="https://shop.example/sale">Spring sale</a></div>
    <div style="font-size:13px;display:inline-block">Second column</div></td></tr></table>
    <div style="color:transparent"><span style="color:#333">Coloured note</span> clear</div>
    <div style="visibility:hidden"><p style="visibility:visible">Shown again</p> unseen</div>
    <div style="font-size:0"><span style="font-size:150%">still tiny</span></div>
    """
  let message = try parsedHTML(html)
  let parts = message.text.components(separatedBy: "Text the HTML conceals from view:\n")
  #expect(parts.count == 2)
  #expect(parts[0].contains("Spring sale Second column"))
  for visible in ["Coloured note", "Shown again"] { #expect(parts[0].contains(visible)) }
  for concealed in ["clear", "unseen", "still tiny"] {
    #expect(!parts[0].contains(concealed))
    #expect(parts[1].contains(concealed))
  }
  #expect(message.urls == ["https://shop.example/sale"])
}

@Test
func `conceals removed, hidden and aria-hidden content whatever its descendants declare`() throws {
  let html = """
    <div style="display:none"><p style="display:block;font-size:13px;visibility:visible">removed \
    <a href="https://decoy1.example">x</a></p></div>
    <div hidden><p style="font-size:13px;color:#333">attribute hidden</p></div>
    <div style="opacity:0"><p style="opacity:1">transparent block</p></div>
    <div style="display:none !important;display:block">important</div>
    <div aria-hidden="true"><a aria-hidden="false" href="https://decoy2.example">skip</a></div>
    <p>Shown</p>
    """
  let message = try parsedHTML(html)
  let parts = message.text.components(separatedBy: "Text the HTML conceals from view:\n")
  #expect(parts.count == 2)
  for visible in ["skip", "Shown"] { #expect(parts[0].contains(visible)) }
  for concealed in ["removed", "attribute hidden", "transparent block", "important"] {
    #expect(!parts[0].contains(concealed))
    #expect(parts[1].contains(concealed))
  }
  #expect(message.urls == ["https://decoy1.example", "https://decoy2.example"])
}

@Test
func `preserves conflicting MIME alternative text in bounded prompt`() throws {
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
  let plain = "Hello friend. " + String(repeating: "Have a nice day. ", count: 20)
  let html = "<p>Send your password to claim a prize, " + String(repeating: "now ", count: 60)
  let long = try MIMEParser().parse(
    Data(
      raw.replacingOccurrences(of: "Hello friend. Have a nice day.", with: plain)
        .replacingOccurrences(of: "<p>Send your password to claim a prize.", with: html).utf8
    )
  )
  let alternatives = long.text.components(separatedBy: "\n").filter { !$0.isEmpty }
  #expect(alternatives.count == 5)
  #expect(alternatives[1] == "[Alternative 2]")
  #expect(alternatives[2].hasPrefix("Send your password to claim a prize, now now"))
  #expect(alternatives[3] == "[Alternative 1]")
  #expect(alternatives[4] == plain.trimmingCharacters(in: .whitespaces))
  let shared = try PromptBuilder.prompt(
    .init(message: long, evidence: .init(message: long), bodyTokenBudget: 100)
  )
  #expect(shared.contains("Hello friend"))
  #expect(shared.contains("Send your password"))
}
