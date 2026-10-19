import Foundation
import Testing
import SpamWiseCore
import MailIntegration
@testable import SpamWiseCommon

/// A record of a message SpamWise handled with `action`, ending in `outcome`.
private func record(
  _ action: MailAction,
  outcome: ActionOutcome = .applied,
  path: DecisionPath = .model
) -> DecisionRecord {
  DecisionRecord(
    identity: MessageIdentity(accountID: "account", contentHash: "message"),
    sender: "offers@shop.example",
    decision: .init(label: nil, action: action, reason: .model("Repeated promotion")),
    outcome: outcome,
    path: path
  )
}

/// A selected message; an unreadable one has no text.
private func message(_ id: String, readable: Bool = true) -> ReviewMessage {
  ReviewMessage(
    envelope: MailEnvelope(identity: .init(accountID: "account", contentHash: id), raw: Data()),
    subject: readable ? "Offer" : nil,
    sender: readable ? "offers@shop.example" : nil,
    text: readable ? "Save today" : nil
  )
}

@Suite
struct `Junk provenance` {
  @Test
  func `credits SpamWise for its latest move to Junk`() {
    let provenance = JunkProvenance(records: [record(.moveToJunk), record(.moveToInbox)])
    #expect(provenance == .spamWise(.model("Repeated promotion")))
  }

  @Test
  func `credits the user for a correction to Junk`() {
    #expect(JunkProvenance(records: [record(.moveToJunk, path: .correction)]) == .userCorrection)
  }

  @Test
  func `blames another filter when SpamWise last moved the message to the Inbox`() {
    let provenance = JunkProvenance(records: [record(.moveToInbox), record(.moveToJunk)])
    #expect(provenance == .elsewhere)
  }

  @Test
  func `ignores moves that dry run or a failure kept from happening`() {
    let provenance = JunkProvenance(records: [
      record(.moveToJunk, outcome: .dryRun), record(.moveToJunk, outcome: .failed)
    ])
    #expect(provenance == .elsewhere)
  }

  @Test
  func `is unknown without any record`() {
    #expect(JunkProvenance(records: []) == .unknown)
  }
}

@Suite
struct `Selected-message batches` {
  @Test
  func `skip unreadable and unverified messages individually`() {
    let batch = SelectionBatch(
      label: .junk,
      scope: .address,
      messages: [message("a"), message("b"), message("c", readable: false)],
      unverifiedIDs: [message("b").id],
      unreadableCount: 0
    )
    #expect(batch.skipReason(for: message("a")) == nil)
    #expect(batch.skipReason(for: message("b")) == .unverifiedSender)
    #expect(batch.skipReason(for: message("c", readable: false)) == .unreadable)
  }

  @Test
  func `summarize corrections, unmoved mail and skipped messages`() {
    let messages = [message("a"), message("b"), message("c")]
    let batch = SelectionBatch(
      label: .junk,
      scope: .address,
      messages: messages,
      unverifiedIDs: [],
      unreadableCount: 1
    )
    let summary = batch.summary(of: [
      .init(message: messages[0], outcome: .corrected(record(.moveToJunk), conflict: nil)),
      .init(
        message: messages[1],
        outcome: .corrected(record(.moveToJunk, outcome: .failed), conflict: nil)
      ),
      .init(message: messages[2], outcome: .skipped(.unverifiedSender))
    ])
    #expect(summary.hasPrefix("Marked 2 of 4 messages as Junk. Mail couldn’t move 1 of them."))
    #expect(summary.contains("Skipped 1."))
  }
}

@MainActor
@Suite
struct `Decision corrections` {
  @Test
  func `wait for confirmation before blocking an unverified sender`() {
    let corrections = CorrectionsModel(services: .preview())
    let unverified = record(.none)
    corrections.correct(unverified, label: .junk)
    #expect(corrections.pendingDecision?.record.id == unverified.id)
    #expect(!corrections.decision.isBusy)
    corrections.cancelPendingDecision()
    #expect(corrections.pendingDecision == nil)
  }

  @Test
  func `save a Good correction without asking`() {
    let corrections = CorrectionsModel(services: .preview())
    corrections.correct(record(.none), label: .inbox)
    #expect(corrections.pendingDecision == nil)
    #expect(corrections.decision.isBusy)
  }
}

@MainActor
@Suite
struct `Reviewed-message capacity` {
  @Test
  func `counts the corrections an import would displace`() {
    let shared = SharedStateModel(store: nil, reportsMissingStore: false)
    let corpus = CorpusModel(services: .preview(), shared: shared)
    shared.state.reviewedLabels = (0..<RetentionLimits.reviewedLabels - 2).map {
      ReviewedLabel(identity: .init(accountID: "account", contentHash: "\($0)"), label: .junk)
    }
    #expect(corpus.correctionsDisplaced(importing: 2) == 0)
    #expect(corpus.correctionsDisplaced(importing: 5) == 3)
  }
}

@MainActor
@Suite
struct `Selected-message corrections` {
  @Test
  func `overlap each message's wait for Mail to show it in Junk`() async throws {
    let mail = SelectedInbox(count: CorrectionsModel.maximumOverlappingCorrections)
    let corrections = CorrectionsModel(services: try await services(mail: mail))
    try await markJunkCorrected(mail.count, with: corrections)
    let records = corrections.selectionResults.map(\.record)
    #expect(records.map { $0?.outcome } == Array(repeating: .applied, count: mail.count))
    #expect(records.map { $0?.readStatusOutcome } == Array(repeating: .applied, count: mail.count))
    #expect(corrections.selectionResults.map(\.message.subject) == mail.subjects)
  }

  @Test
  func `ask before blocking senders whose check fails`() async throws {
    let mail = SelectedInbox(count: 2)
    let corrections = CorrectionsModel(
      services: try await services(mail: mail, checksSendersWith: unreadableStore())
    )
    #expect(corrections.correctSelection(.junk) {})
    await corrections.selection.run { nil }.value
    #expect(try #require(corrections.pendingSelection).unverifiedIDs.count == mail.count)
    #expect(corrections.selectionResults.isEmpty)
  }

  /// Corrects Mail's selection as Junk, confirming its unverified senders, and waits for the batch.
  private func markJunkCorrected(_ count: Int, with corrections: CorrectionsModel) async throws {
    #expect(corrections.correctSelection(.junk) {})
    await corrections.selection.run { nil }.value
    #expect(try #require(corrections.pendingSelection).unverifiedIDs.count == count)
    corrections.confirmPendingSelection(skippingUnverified: false)
    await corrections.selection.run { nil }.value
  }

  /**
   Live services over a temporary store that acts on `mail`'s account and marks Junk read.

   The pipeline checks senders against `pipelineStore` when one is given, or else the same store.
   */
  private func services(mail: SelectedInbox, checksSendersWith pipelineStore: Store? = nil)
    async throws -> AppServices
  {
    let store = try Store(url: temporaryStoreURL())
    try await StateRepository.update(store) { state in
      state.settings.dryRun = false
      state.settings.validatedAccounts = [SelectedInbox.accountID]
      state.settings.mailOptions.markJunkRead = true
    }
    return AppServices(
      store: store,
      pipeline: Pipeline(
        store: pipelineStore ?? store,
        classifier: MockClassifier(verdict: .init(label: .junk, confidence: 99, reason: "Unused"))
      ),
      appleMail: AppleMailAdapter(
        runner: mail,
        moveSettlingTime: .seconds(2),
        observationInterval: .milliseconds(10)
      ),
      preferences: try #require(UserDefaults(suiteName: "codes.tim.SpamWise.UnitTests.\(UUID())")),
      uiTesting: true
    )
  }

  private func temporaryStoreURL() -> URL {
    FileManager.default.temporaryDirectory
      .appending(path: "SpamWise-UnitTests-\(UUID())/state.store")
  }

  /// A store whose location is a directory, so every transaction on it fails.
  private func unreadableStore() throws -> Store {
    let url = temporaryStoreURL()
    let store = try Store(url: url)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return store
  }
}

/**
 Mail with messages selected in the Inbox.

 A message moved to Junk appears there only once every selected message has been moved, so a
 batch that waits for each move to settle before starting the next never sees one confirmed.
 */
private actor SelectedInbox: AppleEventRunner {
  static let accountID = "account"
  nonisolated let count: Int
  nonisolated let subjects: [String?]
  private var messages: [Message]
  private var moved = 0

  init(count: Int) {
    self.count = count
    let messages = (1...count).map(Message.init)
    self.messages = messages
    subjects = messages.map(\.subject)
  }

  func run(_ request: MailRequest) throws -> ScriptValue {
    switch request {
      case .selection:
        return .list([.integer(messages.count), .list(messages.map(\.row))])
      case let .find(_, messageID, _, mailbox):
        return .list(
          messages.filter { $0.messageID == messageID && (mailbox ?? $0.mailbox) == $0.mailbox }
            .map(\.row)
        )
      case let .apply(.moveToJunk, target):
        return .boolean(move(target))
      case .apply(.markRead, _):
        return .boolean(true)
      case let .observe(_, .junk, messageID) where moved == messages.count:
        return .list(
          messages.filter { $0.messageID == messageID && $0.mailbox == "Junk" }.map(\.row)
        )
      case .observe:
        return .list([])
      default:
        throw IntegrationError.scriptFailed
    }
  }

  private func move(_ target: MailMessageLocation) -> Bool {
    guard let index = messages.firstIndex(where: { $0.messageID == target.messageID }) else {
      return false
    }
    messages[index].mailbox = "Junk"
    moved += 1
    return true
  }

  private struct Message {
    let messageID: String
    let subject: String?
    let localID: Int
    var mailbox = "Inbox"

    var source: String {
      "From: offers@shop.example\r\nMessage-ID: \(messageID)\r\nSubject: \(subject ?? "")\r\n\r\nSave."
    }
    var row: ScriptValue {
      .list([
        .string(SelectedInbox.accountID), .string(mailbox), .integer(localID), .string(messageID),
        .integer(source.utf8.count), .string(source)
      ])
    }

    init(_ number: Int) {
      messageID = "<offer\(number)@shop.example>"
      subject = "Offer \(number)"
      localID = number
    }
  }
}
