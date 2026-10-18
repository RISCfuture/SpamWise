import Foundation
import Observation
import SpamWiseCore
import MailIntegration

/// Corrections of recorded decisions and of the messages selected in Mail.
@MainActor @Observable final class CorrectionsModel {
  /// Corrections and undo requested from a decision's inspector.
  let decision = TrackedOperation()
  /// Correcting the messages selected in Mail.
  let selection = TrackedOperation()
  /// Per-message results of the latest selected-message correction.
  private(set) var selectionResults: [MailCorrectionResult] = []
  @ObservationIgnored private let services: AppServices

  init(services: AppServices) { self.services = services }

  private static func overridingRuleWarning(_ rule: SenderRule) -> String {
    rule.scope == .domain
      ? String(
        localized: "Your rule for the domain \(rule.value) still decides this sender’s mail."
      )
      : String(localized: "Your rule for \(rule.value) still decides this sender’s mail.")
  }

  /// Corrects `record` and requests its Mail action; the correction is saved even if Mail fails.
  func correct(_ record: DecisionRecord, label: MailLabel, scope: RuleScope = .address) {
    decision.run { [self] in
      let pipeline = try services.requirePipeline()
      var adapter: (any MailClientAdapter)?, adapterFailure: String?
      do {
        adapter = try await services.adapter(for: record)
      } catch {
        adapterFailure = OperationFailure.describe(error)
      }
      let result = try await pipeline.correct(
        recordID: record.id,
        label: label,
        scope: scope,
        adapter: adapter
      )
      let overriding = try? await pipeline.overridingRule(for: result)
      return
        ([String(localized: "Correction saved. Mail action: \(result.outcome.localizedTitle).")]
        + [result.actionError, adapterFailure, overriding.map(Self.overridingRuleWarning)]
        .compactMap(\.self)).joined(separator: " ")
    }
  }

  /// Restores the rules and learning saved before the latest correction; mail does not move.
  func undoLatestCorrection() {
    decision.run { [self] in
      try await CorrectionUndo.apply(store: services.requireStore())
      return String(
        localized: "Correction undone. Use a separate correction to request a Mail action."
      )
    }
  }

  /// Corrects each message selected in Mail, collecting one result per message.
  func correctSelection(_ label: MailLabel) {
    selection.run { [self] in
      let pipeline = try services.requirePipeline()
      selectionResults = []
      let selected = try await services.appleMail.selectedMessages()
      for reviewed in await ReviewMessage.load(selected.messages) {
        try Task.checkCancellation()
        selectionResults.append(
          await correct(reviewed, label: label, pipeline: pipeline)
        )
      }
      return selected.unavailableCount > 0
        ? ScanCoordinator.unreadableStatus(selected.unavailableCount) : nil
    }
  }

  private func correct(
    _ reviewed: ReviewMessage,
    label: MailLabel,
    pipeline: Pipeline
  ) async -> MailCorrectionResult {
    let message = reviewed.envelope
    do {
      let record = try await pipeline.correct(
        envelope: message,
        label: label,
        adapter: services.appleMail
      )
      return .init(id: message.identity.key, subject: reviewed.displaySubject, record: record)
    } catch {
      return .init(
        id: message.identity.key,
        subject: reviewed.displaySubject,
        record: nil,
        error: OperationFailure.describe(error)
      )
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
