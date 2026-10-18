import Foundation
import SpamWiseCore

@MainActor enum PreviewHelper {

  static var record: DecisionRecord {
    DecisionRecord(
      identity: .init(accountID: "preview", contentHash: "preview"),
      sender: "newsletter@example.org",
      subject: "Your weekly digest",
      verdict: .init(label: .review, confidence: 73, reason: "Relationship is unknown"),
      decision: .init(
        label: .review,
        action: .orangeFlag,
        reason: .model("Relationship is unknown")
      ),
      outcome: .dryRun,
      path: .model
    )
  }

  static var failedRecord: DecisionRecord {
    var record = DecisionRecord(
      identity: .init(accountID: "preview", contentHash: "failed-preview"),
      sender: "offers@shop.example",
      subject: "An unwanted offer",
      verdict: .init(label: .junk, confidence: 99, reason: "Repeated unwanted promotion"),
      decision: .init(
        label: .junk,
        action: .moveToJunk,
        reason: .model("Repeated unwanted promotion")
      ),
      outcome: .failed,
      path: .model
    )
    record.actionError = "Mail could not confirm the action."
    return record
  }

  static var sharedProviderRecord: DecisionRecord {
    let raw = Data("From: friend@gmail.com\r\nSubject: Dinner\r\n\r\nSee you at seven".utf8)
    return DecisionRecord(
      identity: .init(accountID: "preview", contentHash: "shared-provider-preview"),
      sender: "friend@gmail.com",
      subject: "Dinner",
      evidence: (try? MIMEParser().parse(raw)).map { EvidenceBundle(message: $0) },
      decision: .init(
        label: .review,
        action: .orangeFlag,
        reason: .model("Relationship is unknown")
      ),
      outcome: .dryRun,
      path: .model
    )
  }

  static var unclassifiedRecord: DecisionRecord {
    DecisionRecord(
      identity: .init(accountID: "preview", contentHash: "unclassified-preview"),
      decision: .init(label: nil, action: .none, reason: .classificationFailed(.consentRequired)),
      outcome: .unclassified
    )
  }

  static var threatAssessment: ThreatAssessment? {
    let raw = Data("From: example@example.org\r\nSubject: Preview\r\n\r\nSynthetic preview".utf8)
    guard let message = try? MIMEParser().parse(raw) else { return nil }
    return try? ThreatAssessment(
      input: .init(message: message, accountID: "preview", evidence: .init(message: message)),
      detector: .init(
        implementation: "Preview",
        model: "Synthetic",
        preprocessing: "Text",
        policy: "Preview"
      ),
      findings: [
        .init(
          kind: .phishing,
          status: .detected,
          reason: "Synthetic credential lure",
          coverage: "Preview text only"
        )
      ]
    )
  }

  static var correctedRecord: DecisionRecord {
    var record = failedRecord
    record.correctedLabel = .inbox
    return record
  }

  static var assessedRecord: DecisionRecord {
    var record = failedRecord
    record.threats = threatAssessment
    return record
  }

  static var corrections: [CorrectionExample] {
    [
      CorrectionExample(
        sender: "offers@shop.example",
        domain: "shop.example",
        subject: "Weekend clearance",
        excerpt: "Save on every order this weekend only.",
        label: .junk,
        promptScope: .account("preview")
      ),
      CorrectionExample(
        sender: "newsletter@shop.example",
        domain: "shop.example",
        subject: "A new collection",
        excerpt: "Meet our new autumn collection.",
        label: .junk,
        promptScope: .account("preview")
      ),
      CorrectionExample(
        sender: "offers@shop.example",
        domain: "shop.example",
        subject: "Last chance savings",
        excerpt: "Your last chance to save ends tonight.",
        label: .junk,
        promptScope: .account("preview")
      )
    ]
  }

  static var rule: SenderRule {
    .init(scope: .address, value: "newsletter@example.org", disposition: .allow)
  }
  static var contentRule: ContentRule {
    var rule = ContentRule()
    rule.pattern = "weekend clearance"
    return rule
  }

  static var reviewedLabels: [ReviewedLabel] {
    var imported = ReviewedLabel(
      identity: .init(accountID: nil, contentHash: "imported-preview"),
      label: .junk
    )
    imported.origin = .reviewedImport
    return [
      ReviewedLabel(identity: .init(accountID: "preview", contentHash: "preview"), label: .inbox),
      imported
    ]
  }

  /// Parsed selected or Junk messages: a promotion, a newsletter and an unreadable message.
  static var reviewMessages: [ReviewMessage] {
    [
      reviewMessage("offers@shop.example", "Weekend clearance", "Save on every order."),
      reviewMessage("news@club.example", "Club news", "Our autumn meeting is on Friday."),
      ReviewMessage(
        envelope: MailEnvelope(
          identity: .init(accountID: "preview", contentHash: "unreadable"),
          raw: Data()
        ),
        subject: nil,
        sender: nil,
        text: nil
      )
    ]
  }

  static var selectionResults: [SelectionCorrectionResult] {
    let messages = reviewMessages
    var moved = record
    moved.outcome = .applied
    return [
      .init(message: messages[0], outcome: .corrected(moved, conflict: nil)),
      .init(
        message: messages[1],
        outcome: .corrected(
          failedRecord,
          conflict: SenderRule(scope: .domain, value: "club.example", disposition: .allow)
        )
      ),
      .init(message: messages[2], outcome: .skipped(.unreadable))
    ]
  }

  static var unverifiedSelection: SelectionBatch {
    let messages = reviewMessages
    return SelectionBatch(
      label: .junk,
      scope: .address,
      messages: messages,
      unverifiedIDs: [messages[0].id],
      unreadableCount: 0
    )
  }

  static func spamhaus(_ transport: SpamhausTransport) -> ExternalEvidenceSettings {
    var configuration = ExternalEvidenceSettings()
    configuration.spamhausTransport = transport
    return configuration
  }

  /// Feature models over preview services, without a store, with fixture Activity and state.
  static func model(
    onboarding: Bool = false,
    paused: Bool = false,
    empty: Bool = false,
    transport: MailTransport = .appleMail,
    backend: ModelBackend = .claude,
    suggestions: Bool = false,
    reviewed: Bool = false,
    spendingLimitReached: Bool = false
  ) -> AppModel {
    let model = AppModel(services: .preview(), activityFixtures: empty ? [] : [record])
    let shared = model.shared
    shared.spending = spending(limitReached: spendingLimitReached)
    shared.state.settings.onboardingComplete = !onboarding
    shared.state.settings.paused = paused
    shared.state.settings.advancedOptions.transport = transport
    shared.state.settings.advancedOptions.backend = backend
    shared.state.rules = empty ? [] : [rule]
    shared.state.corrections = suggestions ? corrections : []
    shared.state.reviewedLabels = reviewed ? reviewedLabels : []
    return model
  }

  /**
   A dry run with a Junk, a Review and a Good decision and one unreadable message, or, with
   `consentRequired`, a message left unclassified because mail sharing is off instead.
   */
  static func dryRun(consentRequired: Bool = false) -> MailPreview {
    var junk = failedRecord
    junk.outcome = .dryRun
    junk.actionError = nil
    var good = sharedProviderRecord
    good.decision = .init(label: .inbox, action: .none, reason: .gate(.contact))
    good.outcome = .noAction
    return MailPreview(
      records: [junk, record, good] + (consentRequired ? [unclassifiedRecord] : []),
      unavailableCount: consentRequired ? 0 : 1
    )
  }

  /// A Junk review showing one page with each kind of provenance.
  static func junkReview() -> JunkReviewModel {
    let review = model().junkReview
    let messages = reviewMessages
    review.preview(
      accountID: "preview",
      rows: [
        JunkReviewRow(message: messages[0], provenance: .spamWise(.model("Repeated promotion"))),
        JunkReviewRow(message: messages[1], provenance: .elsewhere),
        JunkReviewRow(message: messages[2], provenance: .unknown)
      ],
      total: 45
    )
    return review
  }

  private static func reviewMessage(_ sender: String, _ subject: String, _ text: String)
    -> ReviewMessage
  {
    ReviewMessage(
      envelope: MailEnvelope(
        identity: .init(accountID: "preview", contentHash: subject),
        raw: Data()
      ),
      subject: subject,
      sender: sender,
      text: text
    )
  }

  static func spending(limitReached: Bool) -> MonthlySpending {
    var spending = MonthlySpending(month: .init(containing: .now))
    spending.committedMicroUSD = limitReached ? 5_000_000 : 1_380
    spending.limitMicroUSD = limitReached ? 5_000_000 : nil
    spending.limitReached = limitReached
    return spending
  }
}
