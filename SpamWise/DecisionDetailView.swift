import SwiftUI
import SpamWiseCore
import UniformTypeIdentifiers

struct DecisionDetailView: View {
  let row: DecisionRecord
  let corrections: CorrectionsModel
  let messages: MessageAccessModel
  let shared: SharedStateModel
  let activity: ActivityModel
  /// Shows a message preview where this detail is presented.
  let presentPreview: @MainActor (MessagePreview) -> Void

  var body: some View {
    Form {
      Section {
        DecisionSummaryView(row: row)
        if row.isRetryable {
          RetryClassificationButton(corrections: corrections, row: row)
        }
      }
      if let threats = row.threats, threats.wasAssessed {
        Section("Threat assessment") {
          ThreatAssessmentView(assessment: threats)
        }
      }
      Section("Correct this decision") {
        CorrectionControls(corrections: corrections, activity: activity, row: row)
        CorrectionPrompts(corrections: corrections, row: row)
        if row.correctionUndone {
          Text("You undid this correction. The message stays where it is in Mail.")
        }
        if let undo = shared.state.correctionUndo, undo.applies(to: row),
          undo.isAvailable(in: shared.state)
        {
          UndoCorrectionButton(corrections: corrections, row: row)
        }
        OperationStatusView(
          operation: corrections.decision,
          identifier: corrections.decisionOutcome.map { "correction.status.\($0.rawValue)" }
            ?? "correction.status"
        )
      }
      MessageAccessSection(row: row, messages: messages, presentPreview: presentPreview)
      Section {
        DisclosureGroup("Decision details") {
          DecisionDiagnosticsView(
            row: row,
            accountName: shared.accountName(for: row.identity.accountID)
          )
        }
      }
    }.formStyle(.grouped)
  }
}

/// The message, its verdict and reason, and what happened in Mail.
private struct DecisionSummaryView: View {
  let row: DecisionRecord

  var body: some View {
    VStack(alignment: .leading) {
      Text(row.displaySubject).font(.headline).textSelection(.enabled)
      Text(row.displaySender).foregroundStyle(.secondary).textSelection(.enabled)
    }
    LabeledContent("Date") { Text(row.date, format: .dateTime) }
    VStack(alignment: .leading) {
      VerdictBadge(label: row.effectiveLabel)
      if row.wasCorrected {
        Text("SpamWise said: \(VerdictBadge.title(for: row.decision.label))")
          .foregroundStyle(.secondary)
      }
      Text(row.decision.reason.localizedDescription).textSelection(.enabled)
    }
    if let category = row.verdict?.category, category != .unknown {
      LabeledContent("Kind of mail", value: category.localizedName)
        .accessibilityIdentifier("decision.category")
    }
    if let preference = row.decision.preference {
      LabeledContent("Your preference", value: preference.localizedDescription)
    }
    LabeledContent("Outcome", value: row.outcome.localizedTitle)
      .accessibilityIdentifier("correction.outcome")
    if let error = row.actionError { WarningLabel(verbatim: error) }
    if let outcome = row.readStatusOutcome {
      LabeledContent("Marked as read", value: outcome.localizedTitle)
    }
    if let error = row.readStatusError { WarningLabel(verbatim: error) }
  }
}

/// Classifies an unclassified message again, for example after a provider outage.
private struct RetryClassificationButton: View {
  let corrections: CorrectionsModel
  let row: DecisionRecord

  var body: some View {
    Button("Classify Again") { corrections.retryClassification(row) }
      .disabled(!corrections.canRetry(row))
      .help("Checks this message again. Dry run and Pause still apply.")
      .accessibilityIdentifier("correction.retry")
  }
}

/// Reads the message from its mail integration to preview, open or export it.
private struct MessageAccessSection: View {
  let row: DecisionRecord
  let messages: MessageAccessModel
  let presentPreview: @MainActor (MessagePreview) -> Void
  @State private var source: EmailSourceDocument?
  @State private var exporting = false
  @State private var exportFailure: OperationStatus?

  var body: some View {
    Section {
      Button("Preview Message") { messages.preview(row, present: presentPreview) }
      if messages.canOpenInMail(row) {
        Button("Open in Mail") { messages.open(row) }
      }
      Button("Export Raw Source…") {
        messages.exportSource(row) { data in
          source = EmailSourceDocument(data: data); exporting = true
        }
      }
      if messages.operation.isBusy {
        ProgressView { Text("Reading the message…") }.labelsHidden().controlSize(.small)
      }
      OperationStatusView(operation: messages.operation)
      StatusLabel(status: exportFailure)
    }
    .fileExporter(
      isPresented: $exporting,
      document: source,
      contentType: EmailSourceDocument.contentType,
      defaultFilename: "message"
    ) { result in
      exportFailure = ExportResult.status(of: result, failure: "Message source export failed.")
    }
  }
}

/// Undoes the correction this decision shows, naming the sender and verdict it reverts.
private struct UndoCorrectionButton: View {
  let corrections: CorrectionsModel
  let row: DecisionRecord
  @State private var confirming = false

  private var label: String { VerdictBadge.title(for: row.effectiveLabel) }

  var body: some View {
    Button("Undo latest correction…") { confirming = true }
      .disabled(corrections.decision.isBusy)
      .accessibilityIdentifier("correction.undo")
      .confirmationDialog(
        "Undo marking messages from \(row.displaySender) as \(label)?",
        isPresented: $confirming
      ) {
        Button("Undo Rules and Learning") { corrections.undoLatestCorrection() }
          .accessibilityIdentifier("correction.undo.confirm")
      } message: {
        Text(
          "Rules and examples go back to how they were before that correction. Mail doesn’t move."
        )
      }
  }
}

private struct CorrectionControls: View {
  let corrections: CorrectionsModel
  let activity: ActivityModel
  let row: DecisionRecord

  var body: some View {
    HStack {
      ControlGroup {
        CorrectionButton(corrections: corrections, row: row, label: .inbox)
        CorrectionButton(corrections: corrections, row: row, label: .junk)
        CorrectionButton(corrections: corrections, row: row, label: .review)
      }.disabled(!corrections.canCorrect(row))
      if corrections.decision.isBusy {
        ProgressView { Text("Saving the correction…") }.labelsHidden().controlSize(.small)
      }
    }
    if row.sender == nil {
      Text(
        "Corrections need the sender’s address, which this message doesn’t have. Move it in Mail instead."
      )
    }
    if let correction = row.correctedLabel {
      Text("You marked this \(correction.localizedTitle)")
        .accessibilityIdentifier("correction.label.\(correction.rawValue)")
    }
    HStack {
      DomainCorrectionMenu(corrections: corrections, activity: activity, row: row)
        .disabled(!corrections.canCorrect(row) || row.evidence?.fromDomain == nil)
      Spacer()
      HelpButton(page: "correcting-mistakes")
    }
  }
}

/// One verdict correction, named by its verdict noun and described by its command title.
private struct CorrectionButton: View {
  let corrections: CorrectionsModel
  let row: DecisionRecord
  let label: MailLabel

  var body: some View {
    Button(label.localizedTitle) { corrections.correct(row, label: label) }
      .accessibilityLabel(label.correctionTitle)
      .help(label.correctionTitle)
      .accessibilityIdentifier(Self.identifier(for: label))
  }

  private static func identifier(for label: MailLabel) -> String {
    switch label {
      case .inbox: "correction.good"
      case .junk: "correction.junk"
      case .review: "correction.review"
    }
  }
}

/// Domain-wide corrections, confirmed first when the domain is a shared mail provider.
private struct DomainCorrectionMenu: View {
  let corrections: CorrectionsModel
  let activity: ActivityModel
  let row: DecisionRecord
  @State private var pendingLabel: MailLabel?
  @State private var knownSenders = 0

  private var domain: String { row.evidence?.fromDomain ?? "" }

  var body: some View {
    Menu("Correct Entire Domain…") {
      Button("Allow This Domain") { request(.inbox) }
        .accessibilityIdentifier("correction.domain.allow")
      Button("Block This Domain") { request(.junk) }
        .accessibilityIdentifier("correction.domain.block")
    }.accessibilityIdentifier("correction.domain")
      .confirmationDialog(
        "Create a rule for every sender at \(domain)?",
        isPresented: Binding(get: { pendingLabel != nil }, set: { if !$0 { pendingLabel = nil } }),
        presenting: pendingLabel
      ) { label in
        Button(
          label == .inbox ? "Allow every sender at \(domain)" : "Block every sender at \(domain)"
        ) {
          corrections.correct(row, label: label, scope: .domain)
        }
      } message: { _ in
        Text(
          "\(domain) is a shared mail provider, so this rule also applies to unrelated people who use it. Known senders at this domain: \(knownSenders)"
        )
      }
  }

  private func request(_ label: MailLabel) {
    guard SharedMailboxDomains.contains(domain) else {
      corrections.correct(row, label: label, scope: .domain)
      return
    }
    let domain = domain
    Task {
      knownSenders = await activity.knownSenderCounts(atDomains: [domain])[domain, default: 0]
      pendingLabel = label
    }
  }
}

private struct DecisionDiagnosticsView: View {
  let row: DecisionRecord
  let accountName: String

  var body: some View {
    LabeledContent("Decided by", value: row.path.localizedTitle)
    LabeledContent("Policy revision", value: row.revision.formatted())
    LabeledContent("Account", value: accountName)
    LabeledContent("Mailbox", value: row.identity.mailbox ?? String(localized: "Unknown"))
    LabeledContent("Intended action", value: row.decision.action.localizedTitle)
    if let verdict = row.verdict {
      LabeledContent("Confidence") {
        Text(Double(verdict.confidence) / 100, format: .percent)
      }
      LabeledContent("Input tokens", value: verdict.usage.input.formatted())
      LabeledContent("Output tokens", value: verdict.usage.output.formatted())
      LabeledContent("Cached tokens", value: verdict.usage.cached.formatted())
      LabeledContent("Usage") {
        Text(verdict.usage.estimated ? "Estimated" : "Measured")
      }
      LabeledContent("Estimated cost") {
        Text(
          verdict.usage.estimatedCost,
          format: .currency(code: "USD").precision(.fractionLength(6))
        )
      }
    }
    LabeledContent("Latency") {
      Text(
        Measurement(value: row.latency, unit: UnitDuration.seconds),
        format: .measurement(width: .abbreviated, usage: .asProvided)
      )
    }
    if let evidence = row.evidence { EvidenceSummaryView(evidence: evidence) }
  }
}

/// The evidence a decision weighed, as plain statements; unknown signals are left out.
private struct EvidenceSummaryView: View {
  private static let secondsPerDay: Int64 = 86_400
  let evidence: EvidenceBundle

  private var learningSignal: Double? {
    let signals = [evidence.bayesLogOdds, evidence.learnedMargin].compactMap(\.self)
    return signals.isEmpty ? nil : signals.reduce(0, +)
  }

  var body: some View {
    if let domain = evidence.fromDomain {
      LabeledContent("Sender’s domain", value: domain)
    }
    if let domain = evidence.replyToDomain, domain != evidence.fromDomain {
      LabeledContent("Replies go to", value: domain)
    }
    if let domain = evidence.returnPathDomain, domain != evidence.fromDomain {
      LabeledContent("Bounces go to", value: domain)
    }
    LabeledContent("Authentication", value: evidence.senderAuthentication.localizedTitle)
    if let days = evidence.domainAgeDays {
      LabeledContent("Domain registered") {
        Text(
          "\(Duration.seconds(Int64(days) * Self.secondsPerDay), format: .units(allowed: [.days], width: .wide)) ago"
        )
      }
    }
    if let address = evidence.mismatchedDisplayNameAddress {
      LabeledContent("Name shows another address", value: address)
    }
    if evidence.tldIsAbuseHeavy, let tld = evidence.tld {
      LabeledContent("Domain ending", value: String(localized: ".\(tld), often used for spam"))
    }
    if let learningSignal {
      LabeledContent(
        "Learned from your corrections",
        value: Self.description(ofLearningSignal: learningSignal)
      )
    }
  }

  private static func description(ofLearningSignal signal: Double) -> String {
    if signal > 0 {
      String(localized: "Resembles mail you marked Junk")
    } else if signal < 0 {
      String(localized: "Resembles mail you marked Good")
    } else {
      String(localized: "Neither Good nor Junk")
    }
  }
}

/// A verdict as a symbol and its noun; an unclassified decision has its own symbol.
struct VerdictBadge: View {
  let label: MailLabel?
  /// The title of the verdict a correction replaced, when the badge shows a corrected decision.
  var originalTitle: String?

  private var title: String { Self.title(for: label) }

  var body: some View {
    HStack(spacing: 4) {
      Label(title, systemImage: label?.systemImage ?? "questionmark.circle")
        .accessibilityLabel("Verdict: \(title)")
      if let originalTitle {
        Image(systemName: "arrow.uturn.backward")
          .foregroundStyle(.secondary)
          .help("Corrected from \(originalTitle)")
          .accessibilityLabel("Corrected from \(originalTitle)")
      }
    }
  }

  /// The verdict `row` ends with, marked when the user's correction replaced SpamWise's own.
  init(row: DecisionRecord) {
    label = row.effectiveLabel
    originalTitle = row.wasCorrected ? Self.title(for: row.decision.label) : nil
  }

  init(label: MailLabel?) { self.label = label }

  /// The noun of `label`, or Unclassified.
  static func title(for label: MailLabel?) -> String {
    label?.localizedTitle ?? String(localized: "Unclassified")
  }
}

/// A message's raw source, saved as an email file.
private struct EmailSourceDocument: FileDocument {
  /// An `.eml` email message, the type Mail saves.
  static let contentType =
    UTType(filenameExtension: "eml", conformingTo: .emailMessage) ?? .emailMessage
  static var readableContentTypes: [UTType] { [contentType] }
  var data: Data

  init(data: Data) { self.data = data }
  init(configuration: ReadConfiguration) throws {
    guard let data = configuration.file.regularFileContents else {
      throw CocoaError(.fileReadCorruptFile)
    }
    self.data = data
  }
  func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: data)
  }
}

extension DecisionRecord {
  /// The verdict that stands: the user's correction when there is one, else SpamWise's own.
  var effectiveLabel: MailLabel? { correctedLabel ?? decision.label }
  /// Whether the user later corrected this decision to a different verdict than SpamWise's.
  var wasCorrected: Bool {
    path != .correction && correctedLabel != nil && correctedLabel != decision.label
  }
}

#Preview("Decision") { DecisionDetailPreview(row: PreviewHelper.record) }
#Preview("Failed action") { DecisionDetailPreview(row: PreviewHelper.failedRecord) }
#Preview("Unclassified") { DecisionDetailPreview(row: PreviewHelper.unclassifiedRecord) }
#Preview("Assessed threats") { DecisionDetailPreview(row: PreviewHelper.assessedRecord) }
#Preview("Verdicts") {
  VStack(alignment: .leading) {
    ForEach(MailLabel.allCases, id: \.self) { VerdictBadge(label: $0) }
    VerdictBadge(label: nil)
    VerdictBadge(row: PreviewHelper.correctedRecord)
  }.padding()
}
#Preview("Corrections") {
  let model = PreviewHelper.model()
  Form {
    CorrectionControls(
      corrections: model.corrections,
      activity: model.activity,
      row: PreviewHelper.record
    )
  }
}
#Preview("Shared provider corrections") {
  let model = PreviewHelper.model()
  Form {
    CorrectionControls(
      corrections: model.corrections,
      activity: model.activity,
      row: PreviewHelper.sharedProviderRecord
    )
  }
}
#Preview("Sender-less corrections") {
  let model = PreviewHelper.model()
  Form {
    CorrectionControls(
      corrections: model.corrections,
      activity: model.activity,
      row: PreviewHelper.unclassifiedRecord
    )
  }
}
#Preview("Diagnostics") {
  Form { DecisionDiagnosticsView(row: PreviewHelper.record, accountName: "Example account") }
}

/// A decision's detail over preview models.
private struct DecisionDetailPreview: View {
  let row: DecisionRecord
  let model = PreviewHelper.model()

  var body: some View {
    DecisionDetailView(
      row: row,
      corrections: model.corrections,
      messages: model.messages,
      shared: model.shared,
      activity: model.activity
    ) { _ in }
  }
}
