import Foundation
import Synchronization

/**
 Selected-message corrections requested together, which one undo reverts as a unit.

 Pass the same batch to each of its corrections. Its undo restores the rules and learning from
 before the first of them, or, when another change was saved in between, from after that change.
 */
public final class CorrectionBatch: Sendable {
  /// Identifies the batch's corrections in their undo.
  let id = UUID()
  private let saved = Mutex(0)

  /// How many of the batch's corrections have been saved.
  var savedCount: Int { saved.withLock { $0 } }

  /// Creates a batch with no saved corrections.
  public init() {}

  /// Counts a correction of the batch once it is saved.
  func recordSaved() { saved.withLock { $0 += 1 } }
}

extension Pipeline {
  /**
   Corrects an explicitly selected message without first invoking a classifier.

   The message's record is saved with the correction, so a correction that fails leaves no
   record. A Review annotation that SpamWise left on the message is removed like one on a
   corrected Activity record. Corrections given the same `batch` are undone together.
   */
  public func correct(
    envelope: MailEnvelope,
    label: MailLabel,
    scope: RuleScope = .address,
    adapter: (any MailClientAdapter)? = nil,
    trainingPlanID: String? = nil,
    batch: CorrectionBatch? = nil
  ) async throws -> DecisionRecord {
    let message = try MIMEParser().parse(envelope.raw)
    let selection = try await StateRepository.transaction(store) { transaction in
      try transaction.loadClaim(for: envelope.identity)
      let state = transaction.state
      var seed = DecisionRecord(
        identity: envelope.identity,
        sender: message.fromAddress,
        subject: message.subject,
        evidence: EvidenceBundle(
          message: message,
          trustedAuthServers: state.settings.mailOptions.trustedAuthServers(
            for: envelope.identity.accountID
          )
        ),
        decision: .init(label: nil, action: .none, reason: .selectedForCorrection),
        outcome: .noAction,
        path: .selection,
        revision: state.revision
      )
      seed.sampleID = LearningSample.identity(for: message)
      let claimed = state.claimedActions[envelope.identity.key].flatMap { id in
        state.records.first { $0.id == id }
      }
      return (seed: seed, annotation: claimed?.reviewAnnotation)
    }
    var request = CorrectionRequest(
      recordID: selection.seed.id,
      label: label,
      scope: scope,
      trainingPlanID: trainingPlanID
    )
    request.seed = selection.seed
    request.reviewAnnotation = selection.annotation
    request.batch = batch
    return try await correct(request, adapter: adapter, message: message)
  }
}
