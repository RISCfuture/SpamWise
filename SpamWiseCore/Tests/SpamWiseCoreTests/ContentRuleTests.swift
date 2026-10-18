import Foundation
import Testing
import SpamWiseCore

@Test func `orders content rules and skips pathological expressions`() async throws {
  var message = try MIMEParser().parse(fixture("filler-spam"))
  message.subject = "Example newsletter"
  var older = ContentRule()
  older.pattern = "NEWSLETTER"; older.disposition = .allow
  var newer = ContentRule()
  newer.pattern = "^Example.*"; newer.operation = .regularExpression
  newer.updatedAt = older.updatedAt.addingTimeInterval(1)
  #expect(
    ContentRules.evaluate([older, newer], message: message).matching.map(\.id)
      == [newer.id, older.id]
  )
  newer.enabled = false
  #expect(ContentRules.evaluate([older, newer], message: message).matching.map(\.id) == [older.id])
  newer.enabled = true; newer.pattern = "(a+)+$"
  older.pattern = "aaa!"
  message.subject = String(repeating: "a", count: 10_000) + "!"
  let pathological = ContentRules.evaluate([older, newer], message: message)
  #expect(pathological.matching.map(\.id) == [older.id])
  #expect(pathological.skipped == [newer.id: .timeout])
  #expect(pathological.decisive == nil)
  newer.pattern = "a$"
  message.subject = String(repeating: "a", count: 40_000) + "tail"
  #expect(ContentRules.evaluate([newer], message: message) == .init())
  newer.pattern = "a{3}tail$"; older.pattern = "TAIL"
  let windowed = ContentRules.evaluate([older, newer], message: message)
  #expect(windowed.matching.map(\.id) == [newer.id, older.id])
  #expect(windowed.decisive == newer)
  var clusters = older
  let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}"
  clusters.pattern = String(repeating: family, count: 256)
  #expect(throws: ContentRuleError.invalid) { try ContentRules.validate(clusters) }
  let raw = Data(
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
  message = try MIMEParser().parse(raw)
  newer.field = .attachmentNames; newer.pattern = "invoice.pdf"; newer.operation = .contains
  #expect(ContentRules.evaluate([newer], message: message).matching.count == 1)
  newer.pattern = "Invoice 123.html"
  #expect(ContentRules.evaluate([newer], message: message).matching.count == 1)
  newer.field = .recipients; newer.pattern = "José <"
  #expect(ContentRules.evaluate([newer], message: message).matching.count == 1)
  #expect(message.text.isEmpty)
  #expect(message.attachments?.first?.mediaType == "application/pdf")
  newer.field = .subject; newer.pattern = "("; newer.operation = .regularExpression
  newer.disposition = .allow
  older.pattern = "courtesy kit"; older.disposition = .block
  let store = try testStore(), unusable = newer, outranked = older
  try await StateRepository.update(store) { $0.contentRules = [unusable, outranked] }
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

@Test func `imports an exported content rule once`() async throws {
  let store = try testStore()
  var rule = ContentRule(); rule.pattern = "newsletter"
  let archive = try ContentRuleManagement.exportRules([rule])
  try await ContentRuleManagement.importRules(archive, store: store)
  try await ContentRuleManagement.importRules(archive, store: store)
  #expect(try await StateRepository.load(store).contentRules.count == 1)
}

@Test func `turns a content rule off without changing its precedence`() async throws {
  let store = try testStore()
  var rule = ContentRule(); rule.pattern = "newsletter"
  try await ContentRuleManagement.save(rule, store: store)
  let saved = try #require(try await StateRepository.load(store).contentRules.first)
  try await ContentRuleManagement.setEnabled(rule.id, false, store: store)
  let disabled = try #require(try await StateRepository.load(store).contentRules.first)
  #expect(!disabled.enabled)
  #expect(disabled.updatedAt == saved.updatedAt)
}

@Test func `refuses to export an invalid regular expression`() {
  var rule = ContentRule(); rule.pattern = "["; rule.operation = .regularExpression
  #expect(throws: ContentRuleError.invalid) { try ContentRuleManagement.exportRules([rule]) }
}
