import Foundation

/// Explicit labeled corpus operations that never create sender rules or request mail actions.
public enum CorpusManagement {
  private static let maximumBatch = 20
  private static let maximumLabels = 500
  private static let maximumTextCharacters = 16_000
  private static let maximumURLs = 40
  private static let maximumURLCharacters = 2048
  private static let maximumCorrections = 200
  /// Imports a bounded batch of human-reviewed examples, deduplicating by delivery-independent content.
  public static func importMessages(_ messages: [ParsedMessage], label: MailLabel, store: Store)
    async throws
  {
    guard messages.count <= maximumBatch,
      messages.allSatisfy({ !$0.subject.hasPrefix("[SpamWise Probe]") })
    else { throw ParseError.tooLarge }
    let prepared = messages.map { message in
      var bounded = message
      bounded.text = String(message.text.prefix(maximumTextCharacters))
      bounded.urls = message.urls.prefix(maximumURLs).map {
        String($0.prefix(maximumURLCharacters))
      }
      bounded.headers = [:]
      return bounded
    }
    try await StateRepository.update(store) { state in
      var labels = state.reviewedLabels ?? []
      var learning = state.learning ?? LearningState()
      for message in prepared {
        let sampleID = LearningSample.identity(for: message)
        labels.removeAll { ($0.sampleID ?? $0.id) == sampleID }
        let identity = MessageIdentity(accountID: nil, contentHash: message.hash)
        var reviewed = ReviewedLabel(
          identity: identity,
          label: label,
          message: state.settings.advancedOptions.retainReviewedContent ? message : nil,
          sampleID: sampleID
        )
        reviewed.origin = .reviewedImport
        labels.append(reviewed)
        state.corrections.removeAll { $0.sampleID == sampleID }
        learning.forget(sampleID: sampleID)
        learning.recordCorrection(
          message: message,
          evidence: EvidenceBundle(message: message),
          label: label
        )
        var example = CorrectionExample(
          sender: message.fromAddress,
          domain: DomainResolver().domain(ofAddress: message.fromAddress),
          subject: message.subject,
          excerpt: message.text,
          label: label,
          promptScope: .everyAccount
        )
        example.sampleID = sampleID
        state.corrections.append(example)
      }
      guard labels.count <= maximumLabels else { throw ParseError.tooLarge }
      state.reviewedLabels = labels
      state.correctionUndo = nil
      state.learning = learning
      state.corrections = Array(state.corrections.suffix(maximumCorrections))
      state.revision += 1; state.retries.removeAll()
      state.audit(
        .corpusImport,
        detail: "Imported \(prepared.count) explicitly reviewed \(label.rawValue) examples"
      )
    }
  }
  /// Relabels reviewed content and linked features without creating sender rules or moving mail.
  public static func relabel(id: String, label: MailLabel, store: Store) async throws {
    try await StateRepository.update(store) { state in
      guard var reviewed = state.reviewedLabels?.first(where: { $0.id == id }) else {
        throw IntegrationError.unavailable
      }
      let sampleID = reviewed.sampleID ?? reviewed.message.map(LearningSample.identity) ?? id
      reviewed.label = label; reviewed.date = .now
      state.reviewedLabels?.removeAll { $0.id == id }
      state.reviewedLabels?.append(reviewed)
      state.learning?.relabel(sampleID: sampleID, label: label)
      for index in state.corrections.indices where state.corrections[index].sampleID == sampleID {
        state.corrections[index].label = label
      }
      state.correctionUndo = nil
      state.revision += 1; state.retries.removeAll()
      state.audit(
        .corpusImport,
        detail: String(localized: "Relabeled reviewed example: \(label.rawValue)")
      )
    }
  }
  /// Forgets one label and its linked derived learning, retaining explicit sender rules.
  public static func forget(id: String, store: Store) async throws {
    try await StateRepository.update(store) { state in
      guard let label = state.reviewedLabels?.first(where: { $0.id == id }) else {
        throw IntegrationError.unavailable
      }
      let sampleID = label.sampleID ?? label.message.map(LearningSample.identity) ?? id
      state.reviewedLabels?.removeAll { $0.id == id || $0.sampleID == sampleID }
      state.corrections.removeAll { $0.sampleID == sampleID }
      state.learning?.forget(sampleID: sampleID)
      state.correctionUndo = nil
      state.revision += 1; state.retries.removeAll()
      state.audit(
        .corpusForget,
        detail: String(localized: "Forgot linked corpus sample \(sampleID)")
      )
    }
  }
}
