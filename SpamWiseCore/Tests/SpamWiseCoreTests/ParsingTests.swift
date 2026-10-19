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
@Test
func `decodes MIME and folded headers`() async throws {
  let message = try MIMEParser().parse(fixture("encoded"))
  #expect(message.subject == "Café with lunch")
  #expect(message.fromDisplayName == "José")
  #expect(message.text.contains("Café"))
  #expect(message.urls.contains("https://shop.example.co.uk/order"))
  #expect(message.decodingIssues == nil)
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
  for structure in try structuralMessages() {
    let message = try MIMEParser().parse(Data(structure.source.utf8))
    #expect(message.text.trimmingCharacters(in: .whitespacesAndNewlines) == structure.text)
    #expect(message.decodingIssues == structure.issues)
  }
  for ambiguous in [
    "From: a@example.org\nContent-Type: multipart/mixed; boundary=\"a\"; boundary=\"b\"\n\n"
      + "--a\n\nSafe\n--a--\n",
    "From: a@example.org\nContent-Type: multipart/mixed; boundary=a; Boundary*=''b\n\n"
      + "--a\n\nSafe\n--a--\n",
    "From: a@example.org\nContent-Type: text/plain\n"
      + "Content-Type : multipart/alternative; boundary=b\n\n--b\n\nHi\n--b--\n"
  ] {
    let message = try MIMEParser().parse(Data(ambiguous.utf8))
    #expect(message.text.isEmpty)
    #expect(message.decodingIssues == [.ambiguousPartHeaders])
    #expect(message.concealsContent)
  }
  #expect(throws: ParseError.unreadableSender) {
    try MIMEParser().parse(Data("From: friend@example.org\nFrom : evil@attacker.top\n\nHi".utf8))
  }
  let latin1Subject = try MIMEParser().parse(
    Data(Array("From: a@example.org\nSubject: Caf".utf8) + [0xE9] + Array("\n\nBody".utf8))
  )
  #expect(latin1Subject.subject == "Café")
  #expect(latin1Subject.decodingIssues == [.invalidCharacters])
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

@Test
func `parses display-name senders and rejects malformed or oversized messages`() throws {
  for sender in [
    #""friend@example.org"@attacker.example"#, "friend@example.org trailing", "a..b@example.org",
    "a@example..org", "a@example.org, b@example.org", "Jane <a@example.org> <b@example.org>",
    "Jane <a@example.org> trailing", #""Unterminated <a@example.org>"#
  ] {
    #expect(MIMEParser.address(sender) == nil)
  }
  for headers in [
    "From: \"friend@example.org\"@attacker.example", "From: PayPal <alerts@evil.top>>",
    "From: \"service@paypal.com <alerts@evil.top>", "From: <alerts@evil.top (x)>",
    "From: Doe, Jane <jane@example.org>", "From: friend@example.org\nFrom: evil@attacker.top",
    "Subject: No sender"
  ] {
    #expect(throws: ParseError.unreadableSender) {
      try MIMEParser().parse(Data("\(headers)\n\nVerify now.".utf8))
    }
  }
  #expect(MIMEParser.address(#""Friend, Jane" <friend@example.org>"#) == "friend@example.org")
  for sender in [#""PayPal" <x@evil.top>,"#, ", (empty) ,x@evil.top"] {
    let listed = try MIMEParser().parse(Data("From: \(sender)\n\nVerify now.".utf8))
    #expect(listed.fromAddress == "x@evil.top")
  }
  #expect(
    Mailbox.list(#""Doe, Jane" <jane@example.org>, bob@example.org (Bob), not an address"#)
      .map(\.address) == ["jane@example.org", "bob@example.org"]
  )
  let spoof = try MIMEParser().parse(
    Data(
      #"""
      From: "service@paypal.com" (Customer \(Care\)) <Alerts@paypa1-secure.top> (Notice)
      Subject: Account locked

      Verify now.
      """#.utf8
    )
  )
  #expect(spoof.fromAddress == "alerts@paypa1-secure.top")
  #expect(spoof.fromDisplayName == "service@paypal.com")
  #expect(EvidenceBundle(message: spoof).mismatchedDisplayNameAddress == "service@paypal.com")
  for displayName in [
    "Contact service@paypal.com.", "Contact service@paypal.com!", "-service@paypal.com?",
    "service\u{FF20}paypal.com"
  ] {
    let punctuated = try MIMEParser().parse(
      Data("From: \"\(displayName)\" <alerts@paypa1-secure.top>\n\nVerify now.".utf8)
    )
    #expect(
      EvidenceBundle(message: punctuated).mismatchedDisplayNameAddress == "service@paypal.com"
    )
  }
  for sender in [
    #""PayPal" (service@paypal.com) <alerts@paypa1-secure.top>"#,
    "PayPal <alerts@paypa1-secure.top> (service@paypal.com)",
    "PayPal (=?utf-8?q?service=40paypal.com?=) <alerts@paypa1-secure.top>"
  ] {
    let commented = try MIMEParser().parse(Data("From: \(sender)\n\nVerify now.".utf8))
    #expect(commented.fromDisplayName == "PayPal")
    #expect(
      EvidenceBundle(message: commented).mismatchedDisplayNameAddress == "service@paypal.com"
    )
  }
  let accented = try MIMEParser().parse(
    Data("From: Voilà Åsa 株式会社 <shop@example.fr>\n\nBonjour".utf8)
  )
  #expect(accented.fromDisplayName == "Voilà Åsa 株式会社")
  for sender in [
    #""jane@example.org" <jane@example.org>"#, "jane@example.org (Jane)",
    #""support@github.com" <noreply@github.com>"#
  ] {
    let matching = try MIMEParser().parse(Data("From: \(sender)\n\nHello".utf8))
    #expect(EvidenceBundle(message: matching).mismatchedDisplayNameAddress == nil)
  }
  #expect(throws: (any Error).self) { try MIMEParser().parse(Data("not mail".utf8)) }
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
func `excludes scripts and remote images from HTML text`() throws {
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
  #expect(message.urls == ["https://track.example/pixel", "https://example.org"])
  let obscured = try MIMEParser().parse(
    Data(
      ("From: a@example.com\nContent-Type: text/html\n\n"
        + "<!-- https://a.example https://b.example --><p>See zz.example: https://zz.example/x.</p>"
        + "<a href=\"https&#58;//payload.top/login\">a</a><a href=' //relative.top/p '>b</a>"
        + "<a href=\"https:\\\\back.top\\x\">c</a><a href=\"ht&#x74;ps&colon;&sol;&sol;split\n.top\">d</a>"
        + "<a href=\"https://zz.example/x\">again</a><a href=\"mailto:x@y.z\">m</a>").utf8
    )
  )
  #expect(
    obscured.urls == [
      "https://zz.example/x", "https://payload.top/login", "https://relative.top/p",
      "https://back.top/x", "https://split.top"
    ]
  )
  let markup = try MIMEParser().parse(
    Data(
      ("From: a@example.com\nContent-Type: text/html\n\n"
        + "<HEAD><title>hidden</title></HEAD><style>p{}</style><!-- hidden -->a < b<br>"
        + "&lt;b&gt;&#x41;&#66;&amp;lt; &bogus; <scriptx>shown</scriptx>"
        + #"<a href="x>y" title='a>b'>link</a>"#).utf8
    )
  )
  #expect(markup.text == "a < b\n<b>AB&lt; &bogus; shown link")
  for (html, visible) in [
    ("<html><head><title>T</title><body><p>Buy cheap meds now</p>", "Buy cheap meds now"),
    ("<html><head/><body>Legit newsletter body</body>", "Legit newsletter body"),
    ("<!-->Empty comment <!--->closes", "Empty comment closes"),
    ("<!-- x --!>Bang-closed comment", "Bang-closed comment"),
    (#"<x="><p>Buy cheap meds now<img alt="">tail"#, "Buy cheap meds now tail"),
    (#"<p =">Buy cheap meds now <b title="">tail"#, "Buy cheap meds now tail"),
    (#"<!x="> Buy cheap meds now <b title="">tail"#, "Buy cheap meds now tail"),
    ("<script=x>Shown text</script=x>", "Shown text"),
    ("<!--" + String(repeating: "x", count: 400_000) + "-->Padded text", "Padded text")
  ] {
    let message = try MIMEParser().parse(
      Data(("From: a@example.com\nContent-Type: text/html\n\n" + html).utf8)
    )
    #expect(message.text.contains(visible))
  }
  let clock = ContinuousClock()
  for flood in [
    String(repeating: "<!--", count: 475_000), String(repeating: "<a", count: 950_000),
    String(repeating: "<a b=\"", count: 330_000), String(repeating: "<a b='", count: 330_000),
    "<!--" + String(repeating: "-", count: 1_900_000),
    "<script>" + String(repeating: "</scriptx", count: 210_000),
    "<script>" + String(repeating: "</script ", count: 210_000)
  ] {
    let html = Data(("From: a@example.com\nContent-Type: text/html\n\n" + flood).utf8)
    let elapsed = try clock.measure { _ = try MIMEParser().parse(html) }
    #expect(elapsed < .seconds(5))
  }
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
