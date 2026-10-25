import Foundation
import Testing
import SpamWiseCore

@Suite
struct `Content rule evaluation` {
  /// A rule saved before `newer`, matching the fixture subject case-insensitively.
  let older: ContentRule
  /// A regular-expression rule saved one second after `older`.
  let newer: ContentRule
  let message: ParsedMessage

  init() throws {
    var message = try MIMEParser().parse(fixture("filler-spam"))
    message.subject = "Example newsletter"
    var older = ContentRule()
    older.pattern = "NEWSLETTER"; older.disposition = .allow
    var newer = ContentRule()
    newer.pattern = "^Example.*"; newer.operation = .regularExpression
    newer.updatedAt = older.updatedAt.addingTimeInterval(1)
    (self.older, self.newer, self.message) = (older, newer, message)
  }

  @Test
  func `orders matching rules newest first`() {
    #expect(
      ContentRules.evaluate([older, newer], message: message).matching.map(\.id)
        == [newer.id, older.id]
    )
  }

  @Test
  func `ignores a disabled rule`() {
    var disabled = newer
    disabled.enabled = false
    #expect(
      ContentRules.evaluate([older, disabled], message: message).matching.map(\.id) == [older.id]
    )
  }

  @Test
  func `skips a pathological expression and lets no lower rule decide`() {
    var pathological = newer, literal = older, message = message
    pathological.pattern = "(a+)+$"
    literal.pattern = "aaa!"
    message.subject = String(repeating: "a", count: 10_000) + "!"
    let evaluation = ContentRules.evaluate([literal, pathological], message: message)
    #expect(evaluation.matching.map(\.id) == [literal.id])
    #expect(evaluation.skipped == [pathological.id: .timeout])
    #expect(evaluation.decisive == nil)
  }

  @Test
  func `anchors expressions at the end of a subject longer than one window`() {
    var anchored = newer, literal = older, message = message
    message.subject = String(repeating: "a", count: 40_000) + "tail"
    anchored.pattern = "a$"
    #expect(ContentRules.evaluate([anchored], message: message) == .init())
    anchored.pattern = "a{3}tail$"; literal.pattern = "TAIL"
    let windowed = ContentRules.evaluate([literal, anchored], message: message)
    #expect(windowed.matching.map(\.id) == [anchored.id, literal.id])
    #expect(windowed.decisive == anchored)
  }

  @Test
  func `rejects a pattern of more than 256 grapheme clusters`() {
    var clusters = older
    let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}"
    clusters.pattern = String(repeating: family, count: 256)
    #expect(throws: ContentRuleError.invalid) { try ContentRules.validate(clusters) }
  }
}

@Suite
struct `Content rules on MIME headers and attachments` {
  private static let raw = Data(
    """
    From: person@example.org
    To: =?utf-8?q?Jo?= =?utf-8?q?s=C3=A9?= <jose@example.org>
    Content-Type: multipart/mixed; boundary=test

    --test
    Content-Type: application/pdf
    Content-Disposition: attachment; filename="../invoice.pdf"

    Not a real PDF and must not be opened.
    --test
    Content-Type: application/octet-stream
    Content-Disposition: attachment; filename*=UTF-8''Invoice%20123.html

    <html></html>
    --test--

    """.utf8
  )
  let message: ParsedMessage

  init() throws { message = try MIMEParser().parse(Self.raw) }

  @Test(arguments: [
    (ContentRuleField.attachmentNames, "invoice.pdf"),
    (.attachmentNames, "Invoice 123.html"),
    (.recipients, "José <")
  ])
  func `matches decoded attachment names and recipients`(field: ContentRuleField, pattern: String) {
    var rule = ContentRule()
    rule.field = field; rule.pattern = pattern; rule.operation = .contains
    #expect(ContentRules.evaluate([rule], message: message).matching.count == 1)
  }

  @Test
  func `keeps attachment content out of the message text`() {
    #expect(message.text.isEmpty)
    #expect(message.attachments?.first?.mediaType == "application/pdf")
  }
}

@Test
func `leaves the decision to the classifier when an unusable rule outranks a matching one`()
  async throws
{
  var unusable = ContentRule(), outranked = ContentRule()
  unusable.pattern = "("; unusable.operation = .regularExpression; unusable.disposition = .allow
  unusable.updatedAt = outranked.updatedAt.addingTimeInterval(1)
  outranked.pattern = "courtesy kit"; outranked.disposition = .block
  let store = try testStore(), rules = [unusable, outranked]
  try await StateRepository.update(store) { $0.contentRules = rules }
  let pipeline = Pipeline(
    store: store,
    classifier: MockClassifier(verdict: .init(label: .junk, confidence: 99, reason: "lure"))
  )
  _ = await pipeline.process(try envelope(), forceDryRun: true)
  #expect(try await StateRepository.load(store).contentRuleSkips.isEmpty)
  let record = await pipeline.process(try envelope())
  #expect(record.path == .model)
  #expect(record.outcome == .dryRun)
  let state = try await StateRepository.load(store)
  #expect(state.contentRuleSkips == [unusable.id: 1])
  #expect(state.contentRuleHits.isEmpty)
}

@Test(arguments: [
  (sender: SenderRuleCase.addressBlock, content: RuleDisposition.allow, decidedBySender: true),
  (.domainAllow, .block, true),
  (.none, .block, false)
])
func `decides by address rule, then domain rule, then content rule, then Contacts`(
  sender: SenderRuleCase,
  content: RuleDisposition,
  decidedBySender: Bool
) async throws {
  let screened = try await screenContact(content: content, sender: sender.rule, trusted: true)
  let expected: GateReason =
    if let rule = sender.rule {
      .senderRule(scope: rule.scope, disposition: rule.disposition)
    } else {
      .contentRule(id: screened.rule.id, disposition: content, note: nil)
    }
  #expect(screened.record.decision.reason == .gate(expected))
  #expect(screened.state.contentRuleHits == (decidedBySender ? [:] : [screened.rule.id: 1]))
}

@Test(arguments: [
  (
    content: RuleDisposition.allow, trusted: false, label: MailLabel.review,
    path: DecisionPath.model
  ),
  (.allow, true, .inbox, .gate),
  (.block, false, .junk, .gate)
])
func `lets a content Allow rule decide only for an authenticated sender`(
  content: RuleDisposition,
  trusted: Bool,
  label: MailLabel,
  path: DecisionPath
) async throws {
  let screened = try await screenContact(content: content, trusted: trusted, isContact: false)
  #expect(screened.record.path == path)
  #expect(screened.record.decision.label == label)
  #expect(screened.state.contentRuleHits == (path == .gate ? [screened.rule.id: 1] : [:]))
}

/// The sender rules the precedence test saves for the authentic contact.
enum SenderRuleCase: Sendable, CustomTestStringConvertible {
  case none, addressBlock, domainAllow

  var rule: SenderRule? {
    switch self {
      case .none: nil
      case .addressBlock:
        SenderRule(scope: .address, value: "colleague@example.net", disposition: .block)
      case .domainAllow: SenderRule(scope: .domain, value: "example.net", disposition: .allow)
    }
  }

  var testDescription: String {
    switch self {
      case .none: "no sender rule"
      case .addressBlock: "address Block rule"
      case .domainAllow: "domain Allow rule"
    }
  }
}

/**
 Processes the authentic contact's message, whose subject mentions Tuesday, under a content rule
 on Tuesday and an optional sender rule, with a classifier that answers Review.

 - Parameters:
   - trusted: Whether the account trusts the receiving server that authenticated the sender.
   - isContact: Whether the sender is in Contacts.
 */
private func screenContact(
  content: RuleDisposition,
  sender: SenderRule? = nil,
  trusted: Bool,
  isContact: Bool = true
) async throws -> (record: DecisionRecord, state: AppState, rule: ContentRule) {
  let store = try testStore(), message = try envelope("authentic-contact")
  var rule = ContentRule()
  rule.pattern = "Tuesday"; rule.disposition = content
  let address = try MIMEParser().parse(message.raw).fromAddress
  try await StateRepository.update(store) { [rule] state in
    state.contentRules = [rule]
    state.rules = sender.map { [$0] } ?? []
    if isContact { state.contactAddresses = [address]; state.contactsUpdatedAt = .now }
  }
  if trusted {
    try await AuthenticationTrust.save(["mx.example"], accountID: "account-A", store: store)
  }
  let pipeline = Pipeline(
    store: store,
    classifier: MockClassifier(verdict: .init(label: .review, confidence: 50, reason: "unsure"))
  )
  let record = await pipeline.process(message)
  return (record, try await StateRepository.load(store), rule)
}

@Test
func `imports an exported content rule once`() async throws {
  let store = try testStore()
  var rule = ContentRule(); rule.pattern = "newsletter"
  let archive = try ContentRuleManagement.exportRules([rule])
  try await ContentRuleManagement.importRules(archive, store: store)
  try await ContentRuleManagement.importRules(archive, store: store)
  #expect(try await StateRepository.load(store).contentRules.count == 1)
}

@Test
func `turns a content rule off without changing its precedence`() async throws {
  let store = try testStore()
  var rule = ContentRule(); rule.pattern = "newsletter"
  try await ContentRuleManagement.save(rule, store: store)
  let saved = try #require(try await StateRepository.load(store).contentRules.first)
  try await ContentRuleManagement.setEnabled(rule.id, false, store: store)
  let disabled = try #require(try await StateRepository.load(store).contentRules.first)
  #expect(!disabled.enabled)
  #expect(disabled.updatedAt == saved.updatedAt)
}

@Test
func `refuses to export an invalid regular expression`() {
  var rule = ContentRule(); rule.pattern = "["; rule.operation = .regularExpression
  #expect(throws: ContentRuleError.invalid) { try ContentRuleManagement.exportRules([rule]) }
}
