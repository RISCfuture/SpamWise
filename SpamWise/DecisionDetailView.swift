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
        if let undo = shared.state.correctionUndo, undo.isAvailable(in: shared.state) {
          UndoCorrectionButton(corrections: corrections, undo: undo)
        }
        OperationStatusView(operation: corrections.decision, identifier: "correction.status")
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
      VerdictBadge(label: row.decision.label)
      Text(row.decision.reason.localizedDescription).textSelection(.enabled)
    }
    LabeledContent("Outcome", value: row.outcome.localizedTitle)
      .accessibilityIdentifier("correction.outcome")
    if let error = row.actionError {
      Label(error, systemImage: "exclamationmark.triangle")
    }
    if let outcome = row.readStatusOutcome {
      LabeledContent("Marked as read", value: outcome.localizedTitle)
    }
    if let error = row.readStatusError { Text(error) }
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

/// Reads the message from Mail to preview, open or export it.
private struct MessageAccessSection: View {
  let row: DecisionRecord
  let messages: MessageAccessModel
  let presentPreview: @MainActor (MessagePreview) -> Void
  @State private var source: RulesDocument?
  @State private var exporting = false
  @State private var exportFailure: OperationStatus?

  var body: some View {
    Section {
      Button("Preview message") { messages.preview(row, present: presentPreview) }
      Button("Open in Mail") { messages.open(row) }
      Button("Export raw source…") {
        messages.exportSource(row) { data in
          source = RulesDocument(data: data); exporting = true
        }
      }
      if messages.operation.isBusy { ProgressView().controlSize(.small) }
      OperationStatusView(operation: messages.operation)
      StatusLabel(status: exportFailure)
    }
    .fileExporter(
      isPresented: $exporting,
      document: source,
      contentType: .data,
      defaultFilename: "message.eml"
    ) { result in
      exportFailure = ExportResult.status(of: result, failure: "Message source export failed.")
    }
  }
}

private struct UndoCorrectionButton: View {
  let corrections: CorrectionsModel
  let undo: CorrectionUndo
  @State private var confirming = false

  var body: some View {
    Button("Undo latest correction…") { confirming = true }
      .disabled(corrections.decision.isBusy)
      .accessibilityIdentifier("correction.undo")
      .confirmationDialog(
        "Restore the previous rules and learning? Mail will not move.",
        isPresented: $confirming
      ) {
        Button("Undo rules and learning") { corrections.undoLatestCorrection() }
          .accessibilityIdentifier("correction.undo.confirm")
      } message: {
        Text(
          "Restores \(undo.ruleCount) rules and \(undo.exampleCount) examples. Later changes disable undo."
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
      if corrections.decision.isBusy { ProgressView().controlSize(.small) }
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
    Menu("Correct entire domain…") {
      Button("Allow this domain") { request(.inbox) }
        .accessibilityIdentifier("correction.domain.allow")
      Button("Block this domain") { request(.junk) }
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

  private var evidenceDescription: String? {
    guard let evidence = row.evidence, let data = try? JSONEncoder.pretty.encode(evidence) else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

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
    if let evidenceDescription {
      Text("Evidence").font(.headline)
      Text(evidenceDescription).monospaced().textSelection(.enabled)
    }
  }
}

/// A verdict as a symbol and its noun; an unclassified decision has its own symbol.
struct VerdictBadge: View {
  let label: MailLabel?

  private var title: String { label?.localizedTitle ?? String(localized: "Unclassified") }

  var body: some View {
    Label(title, systemImage: label?.systemImage ?? "questionmark.circle")
      .accessibilityLabel("Verdict: \(title)")
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
