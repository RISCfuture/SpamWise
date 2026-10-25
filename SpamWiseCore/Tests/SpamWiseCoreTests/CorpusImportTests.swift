import Foundation
import Testing
import SpamWiseCore

@Suite
struct `Reviewed corpus import` {
  private static let importedCount = 20
  /// A registration age that lookups report for long-established domains.
  private static let establishedDomainAgeDays = 400
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
    #expect(Set(imported.corrections.map(\.excerpt)) == [""])
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

  /// Live corrections whose domain ages were unknown, as without lookups, or found by lookups.
  @Test(arguments: [Int?.none, Self.establishedDomainAgeDays])
  func `learns nothing from account-dependent evidence that imported samples lack`(
    liveDomainAgeDays: Int?
  ) async throws {
    for batch in 1...2 {
      try await CorpusManagement.importMessages(
        examples.map { relabelled($0, subject: "\($0.subject), batch \(batch)") },
        label: .junk,
        store: store
      )
    }
    var learning = try await state().learning
    for index in 0..<(3 * Self.importedCount) {
      let good = relabelled(examples[0], subject: "Dinner plans \(index)")
      learning.recordCorrection(
        message: good,
        evidence: .init(message: good, domainAgeDays: liveDomainAgeDays),
        label: .inbox
      )
    }
    let query = examples[0]
    let unknownAge = learning.estimate(message: query, evidence: .init(message: query))
    let knownAge = learning.estimate(
      message: query,
      evidence: .init(message: query, domainAgeDays: Self.establishedDomainAgeDays)
    )
    #expect(unknownAge.logisticMargin != nil)
    #expect(unknownAge.logisticMargin == knownAge.logisticMargin)
  }

  /// `message` under a new subject, which gives it a new content identity.
  private func relabelled(_ message: ParsedMessage, subject: String) -> ParsedMessage {
    var renamed = message
    renamed.subject = subject
    renamed.hash = stableHash(Data(subject.utf8))
    return renamed
  }
}

@Suite
struct `Junk folder bootstrap` {
  private static func message(from sender: String, subject: String) throws -> ParsedMessage {
    var message = try MIMEParser().parse(fixture("filler-spam"))
    message.fromAddress = sender
    message.subject = subject
    message.hash = stableHash(Data((sender + subject).utf8))
    return message
  }

  @Test
  func `groups Junk by sender domain, or address at shared providers, most frequent first`()
    throws
  {
    var state = AppState()
    state.contactAddresses = ["friend@gmail.com"]
    let messages = try [
      Self.message(from: "deals@news.shop.example", subject: "Newest sale"),
      Self.message(from: "offers@shop.example", subject: "Older sale"),
      Self.message(from: "friend@gmail.com", subject: "Hello"),
      Self.message(from: "stranger@gmail.com", subject: "Hello")
    ]
    let senders = JunkFolderBootstrap.senders(in: messages, state: state)
    #expect(senders.map(\.id) == ["shop.example", "friend@gmail.com", "stranger@gmail.com"])
    #expect(senders[0].messageCount == 2 && senders[0].representative.subject == "Newest sale")
    #expect(senders.map(\.possiblyWanted) == [false, true, false])
  }

  @Test
  func `imports one example per sender in batches without rules`() async throws {
    let store = try testStore()
    let messages = try (0..<25).map {
      try Self.message(from: "news@shop\($0).example", subject: "Sale \($0)")
    }
    let senders = JunkFolderBootstrap.senders(in: messages, state: AppState())
    try await JunkFolderBootstrap.importExamples(from: senders, store: store)
    let state = try await StateRepository.load(store)
    #expect(
      state.reviewedLabels.count == 25 && state.reviewedLabels.allSatisfy { $0.label == .junk }
    )
    #expect(state.rules.isEmpty)
  }
}
