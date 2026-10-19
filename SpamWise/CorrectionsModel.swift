import Foundation
import Observation
import SpamWiseCore
import MailIntegration

/**
 Corrections of recorded decisions and of the messages selected in Mail.

 A Junk correction for a sender whose address couldn’t be verified waits for the user to confirm
 it, because the Block rule it saves could also catch the real sender. After a correction, a
 sender rule that still decides the sender’s mail is offered for removal.
 */
@MainActor
@Observable
final class CorrectionsModel {
  /// How many selected messages are corrected at once; Mail still runs one request at a time.
  static let maximumOverlappingCorrections = 4
  private static let selectionActivityReason = "Correcting selected mail"
  /// Corrections and undo requested from a decision’s inspector.
  let decision = TrackedOperation()
  /// Correcting the messages selected in Mail.
  let selection = TrackedOperation()
  /// Removing a sender rule that overrides a correction.
  let ruleRemoval = TrackedOperation()
  /// The Mail action outcome of the decision correction whose result ``decision`` shows.
  private(set) var decisionOutcome: ActionOutcome?
  /// A decision correction waiting for the user to confirm an unverified sender.
  private(set) var pendingDecision: PendingCorrection?
  /// A rule that still decides the sender’s mail after the latest decision correction.
  private(set) var conflict: RuleConflict?
  /// Selected messages waiting for the user to confirm unverified senders.
  private(set) var pendingSelection: SelectionBatch?
  /// How far the running selected-message correction has got.
  private(set) var selectionProgress: CorrectionProgress?
  /// Per-message results of the latest selected-message correction.
  private(set) var selectionResults: [SelectionCorrectionResult] = []
  /// A summary of the latest selected-message correction, for the menu bar.
  private(set) var selectionSummary: String?
  @ObservationIgnored private let services: AppServices
  /// Results of the running selected-message correction, by position in Mail's selection.
  @ObservationIgnored private var finishedSelection: [Int: SelectionCorrectionResult] = [:]

  init(services: AppServices) { self.services = services }

  private static func savedStatus(_ record: DecisionRecord, failures: [String]) -> String {
    let outcome = record.outcome.localizedTitle
    guard !failures.isEmpty else {
      return String(localized: "Correction saved. Mail action: \(outcome).")
    }
    return String(
      localized: "Correction saved. Mail action: \(outcome). \(failures.joined(separator: " "))"
    )
  }

  private static func unverifiedRequiresConfirmation(_ record: DecisionRecord, _ label: MailLabel)
    -> Bool
  {
    record.correctionWarning(for: label) == .unauthenticatedSender
  }
}

// MARK: - Decision corrections

extension CorrectionsModel {
  /// Whether `record` can be corrected now: it has a sender, isn't a setup check and nothing is running.
  func canCorrect(_ record: DecisionRecord) -> Bool {
    !decision.isBusy && record.path != .verification && record.sender != nil
  }

  /// Whether `record` is an unclassified message that can be classified again now.
  func canRetry(_ record: DecisionRecord) -> Bool { !decision.isBusy && record.isRetryable }

  /// Classifies an unclassified record's message again, under the same dry-run and pause rules.
  func retryClassification(_ record: DecisionRecord) {
    decision.run { [self] in
      decisionOutcome = nil
      let pipeline = try services.requirePipeline()
      let adapter = try await services.adapter(for: record)
      let result = try await pipeline.retryUnclassified(recordID: record.id, adapter: adapter)
      guard let label = result.decision.label else {
        return String(
          localized:
            "SpamWise still couldn’t classify this message: \(result.decision.reason.localizedDescription)"
        )
      }
      return String(
        localized:
          "Classified as \(label.localizedTitle). Mail action: \(result.outcome.localizedTitle)."
      )
    }
  }

  /**
   Corrects `record`; the correction is saved even if Mail fails.

   A Junk correction of an unverified sender waits in ``pendingDecision`` until
   ``confirmPendingDecision()``.
   */
  func correct(_ record: DecisionRecord, label: MailLabel, scope: RuleScope = .address) {
    if Self.unverifiedRequiresConfirmation(record, label) {
      pendingDecision = PendingCorrection(record: record, label: label, scope: scope)
    } else {
      perform(PendingCorrection(record: record, label: label, scope: scope))
    }
  }

  /// Saves the correction the user confirmed despite an unverified sender.
  func confirmPendingDecision() {
    guard let pendingDecision else { return }
    self.pendingDecision = nil
    perform(pendingDecision)
  }

  /// Drops the correction waiting for confirmation; nothing is saved.
  func cancelPendingDecision() { pendingDecision = nil }

  /// Restores the rules and learning saved before the latest correction; mail does not move.
  func undoLatestCorrection() {
    conflict = nil
    decision.run { [self] in
      decisionOutcome = nil
      try await CorrectionUndo.apply(store: services.requireStore())
      return String(
        localized: "Correction undone. Use a separate correction to request a Mail action."
      )
    }
  }

  /// Removes the rule that overrides the latest correction, so the correction decides.
  func removeConflictingRule() {
    guard let conflict else { return }
    self.conflict = nil
    removeRule(conflict.rule)
  }

  /// Keeps the rule that overrides the latest correction.
  func keepConflictingRule() { conflict = nil }

  private func perform(_ correction: PendingCorrection) {
    conflict = nil
    decision.run { [self] in
      decisionOutcome = nil
      let pipeline = try services.requirePipeline()
      let record = correction.record
      var adapter: (any MailClientAdapter)?, adapterFailure: String?
      do {
        adapter = try await services.adapter(for: record)
      } catch {
        adapterFailure = OperationFailure.describe(error)
      }
      let result = try await pipeline.correct(
        recordID: record.id,
        label: correction.label,
        scope: correction.scope,
        adapter: adapter
      )
      if let rule = try? await pipeline.overridingRule(for: result) {
        conflict = RuleConflict(recordID: record.id, rule: rule)
      }
      decisionOutcome = result.outcome
      let failures = [result.actionError, adapterFailure].compactMap(\.self)
      return Self.savedStatus(result, failures: failures)
    }
  }

  private func removeRule(_ rule: SenderRule) {
    ruleRemoval.run { [self] in
      try await RuleManagement.remove(id: rule.id, store: services.requireStore())
      return String(localized: "Removed your rule for \(rule.value).")
    }
  }
}

// MARK: - Selected-message corrections

extension CorrectionsModel {
  /**
   Starts correcting the messages selected in Mail, unless a batch is already running or
   waiting.

   - Parameters:
     - confirm: Called when unverified senders need the user’s confirmation, so the caller can
       show ``pendingSelection``.
   - Returns: Whether the request started; a request made during another batch is rejected.
   */
  @discardableResult
  func correctSelection(
    _ label: MailLabel,
    scope: RuleScope = .address,
    confirm: @escaping @MainActor () -> Void
  ) -> Bool {
    guard !selection.isBusy, pendingSelection == nil else { return false }
    selectionResults = []
    selectionSummary = nil
    selection.run { [self] in
      let pipeline = try services.requirePipeline()
      let batch = try await selectedBatch(label: label, scope: scope, pipeline: pipeline)
      guard batch.unverifiedIDs.isEmpty else {
        pendingSelection = batch
        confirm()
        return nil
      }
      return try await correct(batch, pipeline: pipeline)
    }
    return true
  }

  /// Corrects the waiting selection, blocking or skipping its unverified senders.
  func confirmPendingSelection(skippingUnverified: Bool) {
    guard var batch = pendingSelection else { return }
    pendingSelection = nil
    if !skippingUnverified { batch.unverifiedIDs = [] }
    selection.run { [self] in
      try await correct(batch, pipeline: services.requirePipeline())
    }
  }

  /// Drops the waiting selection; nothing is saved.
  func cancelPendingSelection() { pendingSelection = nil }

  /**
   Stops the running selection before any further message starts.

   Corrections already saved are kept; a move already sent to Mail may be reported unconfirmed.
   */
  func cancelSelection() { selection.cancel() }

  /// Removes `rule`, which overrides a selected-message correction.
  func removeOverridingRule(_ rule: SenderRule) {
    selectionResults = selectionResults.map { $0.withoutConflict(rule) }
    removeRule(rule)
  }

  private func selectedBatch(label: MailLabel, scope: RuleScope, pipeline: Pipeline)
    async throws -> SelectionBatch
  {
    let selected = try await services.appleMail.selectedMessages()
    let messages = await ReviewMessage.load(selected.messages)
    var unverified: Set<String> = []
    for message in messages where message.isReadable {
      let warning = try? await pipeline.correctionWarning(envelope: message.envelope, label: label)
      if warning == .unauthenticatedSender { unverified.insert(message.id) }
    }
    return SelectionBatch(
      label: label,
      scope: scope,
      messages: messages,
      unverifiedIDs: unverified,
      unreadableCount: selected.unavailableCount
    )
  }

  private func correct(_ batch: SelectionBatch, pipeline: Pipeline) async throws -> String {
    selectionProgress = CorrectionProgress(completed: 0, total: batch.messages.count)
    defer { selectionProgress = nil }
    await BackgroundActivity.run(Self.selectionActivityReason) {
      await correctOverlapping(batch, pipeline: pipeline)
    }
    guard !Task.isCancelled else {
      selectionSummary = batch.stoppedSummary(after: selectionResults.count)
      throw CancellationError()
    }
    let summary = batch.summary(of: selectionResults)
    selectionSummary = summary
    return summary
  }

  /**
   Corrects the batch so that each message's wait for Mail to show it moved overlaps the next
   messages' corrections, with up to ``maximumOverlappingCorrections`` in progress.

   A message starts only once the previous one has been saved and its first command sent to
   Mail, because a correction saved before then would supersede it. Results are published in
   Mail's order as they finish. Once cancelled, no further message starts.
   */
  private func correctOverlapping(_ batch: SelectionBatch, pipeline: Pipeline) async {
    finishedSelection = [:]
    let mail = services.appleMail
    await withTaskGroup(of: Void.self) { group in
      var running = 0
      for (index, message) in batch.messages.enumerated() {
        if running == Self.maximumOverlappingCorrections, await group.next() != nil {
          running -= 1
        }
        guard !Task.isCancelled else { break }
        let (sent, signal) = AsyncStream<Void>.makeStream()
        group.addTask { [self] in
          let adapter = CommandReportingMail(mail: mail) { signal.finish() }
          let result = await correct(message, in: batch, pipeline: pipeline, adapter: adapter)
          signal.finish()
          await publish(result, at: index)
        }
        running += 1
        for await _ in sent {}
      }
    }
  }

  private func publish(_ result: SelectionCorrectionResult, at index: Int) {
    finishedSelection[index] = result
    selectionResults = finishedSelection.sorted { $0.key < $1.key }.map(\.value)
    selectionProgress?.completed += 1
  }

  private func correct(
    _ message: ReviewMessage,
    in batch: SelectionBatch,
    pipeline: Pipeline,
    adapter: some MailClientAdapter
  ) async -> SelectionCorrectionResult {
    if let reason = batch.skipReason(for: message) {
      return SelectionCorrectionResult(message: message, outcome: .skipped(reason))
    }
    do {
      let record = try await pipeline.correct(
        envelope: message.envelope,
        label: batch.label,
        scope: batch.scope,
        adapter: adapter
      )
      let conflict = try? await pipeline.overridingRule(for: record)
      return SelectionCorrectionResult(
        message: message,
        outcome: .corrected(record, conflict: conflict)
      )
    } catch {
      return SelectionCorrectionResult(
        message: message,
        outcome: .failed(OperationFailure.describe(error))
      )
    }
  }

  /// Shows `results` as the latest selected-message correction, for previews.
  func preview(
    results: [SelectionCorrectionResult],
    progress: CorrectionProgress? = nil,
    pending: SelectionBatch? = nil
  ) {
    selectionResults = results
    selectionProgress = progress
    pendingSelection = pending
  }
}

/// A decision correction the user asked for, before it is saved.
struct PendingCorrection: Equatable {
  let record: DecisionRecord
  let label: MailLabel
  let scope: RuleScope

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.record.id == rhs.record.id && lhs.label == rhs.label && lhs.scope == rhs.scope
  }
}

/// A sender rule that still decides a sender’s mail against the user’s correction.
struct RuleConflict: Equatable {
  /// The Activity record the user corrected.
  let recordID: UUID
  let rule: SenderRule
}

/// How many messages of a batch have been corrected.
struct CorrectionProgress: Equatable {
  var completed: Int
  let total: Int
  /// The one-based position of the message being corrected.
  var current: Int { min(total, completed + 1) }
}

extension DecisionRecord {
  /// Whether this is an unclassified message, rather than a setup check, that can be classified again.
  var isRetryable: Bool { outcome == .unclassified && path != .verification }
}
