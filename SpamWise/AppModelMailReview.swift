import Foundation
import SpamWiseCore
import MailIntegration

extension AppModel {
  func correctSelection(_ label: MailLabel) {
    guard let pipeline else { return }
    run { [self] in
      let messages = await ReviewMessage.load(try await adapter.selectedMessages())
      correctionResults = []
      showCorrections = true
      for reviewed in messages {
        try Task.checkCancellation()
        let message = reviewed.envelope
        let subject = reviewed.displaySubject
        do {
          let record = try await pipeline.correct(envelope: message, label: label, adapter: adapter)
          correctionResults.append(
            .init(id: message.identity.key, subject: subject, record: record)
          )
        } catch {
          correctionResults.append(
            .init(
              id: message.identity.key,
              subject: subject,
              record: nil,
              error: Self.describe(error)
            )
          )
        }
      }
      status = String(localized: "Selected-message corrections finished. Review each mail outcome.")
    }
  }
  func loadJunk(accountID: String, offset: Int) {
    run { [self] in
      let page = try await adapter.accountPage(
        accountID: accountID,
        offset: offset,
        limit: 20,
        role: "junk mailbox"
      )
      junkMessages = await ReviewMessage.load(page.messages)
      junkTotal = page.total
      status = page.unavailableCount > 0 ? Self.unreadableStatus(page.unavailableCount) : ""
    }
  }
  func restoreReviewedMessage(_ envelope: MailEnvelope) {
    guard let pipeline else { return }
    run { [self] in
      let record = try await pipeline.correct(envelope: envelope, label: .inbox, adapter: adapter)
      status = String(localized: "Correction saved. Mail action: \(record.outcome.localizedTitle).")
      if record.outcome == .applied {
        junkMessages.removeAll { $0.id == envelope.identity.key }
      }
    }
  }
  func openInMail(_ record: DecisionRecord) {
    run { [self] in try await adapter.open(record.identity) }
  }
  func previewMessage(_ record: DecisionRecord) {
    run { [self] in
      guard let envelope = try await adapter.lookup(record.identity) else {
        throw IntegrationError.unavailable
      }
      previewText = try await ReviewMessage.text(of: envelope)
      showPreview = true
    }
  }
}

/// A message parsed once for review display; nil fields mean the message is unreadable.
struct ReviewMessage: Identifiable, Sendable {
  let envelope: MailEnvelope
  let subject: String?
  let text: String?
  var id: String { envelope.identity.key }
  var displaySubject: String {
    guard let subject else { return String(localized: "Unclassified message") }
    return subject.isEmpty ? String(localized: "No subject") : subject
  }

  /// Parses each envelope away from the main actor.
  @concurrent static func load(_ envelopes: [MailEnvelope]) async -> [Self] {
    envelopes.map { envelope in
      let message = try? MIMEParser().parse(envelope.raw)
      return Self(envelope: envelope, subject: message?.subject, text: message?.text)
    }
  }

  /// Parses one message's body text away from the main actor.
  @concurrent static func text(of envelope: MailEnvelope) async throws -> String {
    try MIMEParser().parse(envelope.raw).text
  }
}

extension AppModel {
  func correct(_ record: DecisionRecord, label: MailLabel, scope: RuleScope = .address) {
    guard let pipeline else { return }
    run { [self] in
      let activeAdapter: (any MailClientAdapter)?
      if record.identity.mailboxValidity != nil {
        activeAdapter = try? await configuredIMAPCorrectionAdapter()
      } else {
        activeAdapter = adapter
      }
      let result = try await pipeline.correct(
        recordID: record.id,
        label: label,
        scope: scope,
        adapter: activeAdapter
      )
      status =
        String(localized: "Correction saved. Mail action: \(result.outcome.localizedTitle).")
        + (result.actionError.map { " " + $0 } ?? "")
    }
  }
}
