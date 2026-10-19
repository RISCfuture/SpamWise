import Foundation
import Testing
import SpamWiseCore

@Suite
struct `Reviewed corpus import` {
  private static let importedCount = 20
  private let store: Store
  /// The imported Junk examples, which differ only in subject and carry a List-Unsubscribe header.
  private let examples: [ParsedMessage]
  /// State after importing `examples` into a store that already held one sender rule.
  private let imported: AppState

  init() async throws {
    store = try testStore()
    try await RuleManagement.save(
      scope: .address,
      value: "friend@example.org",
      disposition: .allow,
      store: store
    )
    var message = try MIMEParser().parse(fixture("filler-spam"))
    message.headers["list-unsubscribe"] = ["<mailto:leave@courtesy-kit.lat>"]
    examples = (0..<Self.importedCount).map { index in
      var sample = message
      sample.subject = "Corpus example \(index)"
      sample.hash = stableHash(Data(sample.subject.utf8))
      return sample
    }
    try await CorpusManagement.importMessages(examples, label: .junk, store: store)
    imported = try await StateRepository.load(store)
  }

  private func state() async throws -> AppState { try await StateRepository.load(store) }

  @Test
  func `derives learning features from each complete message`() {
    #expect(imported.learning.samples.count == Self.importedCount)
    #expect(imported.learning.samples.allSatisfy { $0.features.listUnsubscribe == 1 })
  }

  @Test
  func `stores labels without rules, Activity or message text`() {
    #expect(imported.reviewedLabels.count == Self.importedCount)
    #expect(imported.rules.count == 1)
    #expect(imported.records.isEmpty)
    #expect(imported.reviewedLabels.allSatisfy { $0.message == nil })
  }

  @Test
  func `links each label to a correction example and holds some out`() {
    let labels = imported.reviewedLabels
    #expect(
      labels.allSatisfy { label in imported.corrections.contains { $0.sampleID == label.sampleID } }
    )
    let holdsSomeOut = labels.contains(where: \.heldOut)
    #expect(holdsSomeOut)
  }

  @Test
  func `replaces the label of a reimported message whose delivery differs`() async throws {
    var redelivered = examples[0]
    redelivered.hash = "different delivery"
    try await CorpusManagement.importMessages([redelivered], label: .inbox, store: store)
    let labels = try await state().reviewedLabels
    #expect(labels.count == Self.importedCount)
    #expect(labels.last?.label == .inbox)
  }

  @Test
  func `relabels an imported label`() async throws {
    let label = try #require(imported.reviewedLabels.last)
    try await CorpusManagement.relabel(id: label.id, label: .review, store: store)
    #expect(try await state().reviewedLabels.last?.label == .review)
  }

  @Test
  func `forgets an imported label and its learning while keeping sender rules`() async throws {
    let label = try #require(imported.reviewedLabels.last)
    try await CorpusManagement.forget(id: label.id, store: store)
    let forgotten = try await state()
    #expect(forgotten.reviewedLabels.count == Self.importedCount - 1)
    #expect(!forgotten.corrections.contains { $0.sampleID == label.sampleID })
    #expect(!forgotten.learning.samples.contains { $0.id == label.sampleID })
    #expect(forgotten.rules == imported.rules)
  }

  @Test
  func `reports the remaining import capacity`() async throws {
    #expect(
      try await CorpusManagement.capacity(store: store).remainingImports
        == RetentionLimits.reviewedLabels - Self.importedCount
    )
  }
}
