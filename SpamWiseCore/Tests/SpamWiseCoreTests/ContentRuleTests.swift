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
  let record = await pipeline.process(try envelope())
  #expect(record.path == .model)
  #expect(record.outcome == .dryRun)
  let state = try await StateRepository.load(store)
  #expect(state.contentRuleSkips == [unusable.id: 1])
  #expect(state.contentRuleHits.isEmpty)
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
