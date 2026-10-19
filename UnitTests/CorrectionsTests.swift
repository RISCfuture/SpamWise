import Foundation
import Testing
import SpamWiseCore
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
