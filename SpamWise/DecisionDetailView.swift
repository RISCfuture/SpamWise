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
  @State private var source: RulesDocument?
  @State private var exporting = false
  @State private var exportFailure: OperationStatus?

  var body: some View {
    Form {
      Section {
        VStack(alignment: .leading) {
          Text(row.displaySubject).font(.headline).textSelection(.enabled)
          Text(row.displaySender).foregroundStyle(.secondary).textSelection(.enabled)
        }
        VStack(alignment: .leading) {
          VerdictBadge(label: row.decision.label)
          Text(row.decision.reason.localizedDescription).textSelection(.enabled)
        }
        LabeledContent("Outcome", value: row.outcome.localizedTitle)
          .accessibilityIdentifier("correction.outcome")
          .accessibilityValue(row.outcome.rawValue)
        if let error = row.actionError {
          Label(error, systemImage: "exclamationmark.triangle")
        }
        if let outcome = row.readStatusOutcome {
          LabeledContent("Mark-as-read", value: outcome.localizedTitle)
        }
        if let error = row.readStatusError { Text(error) }
      }
      Section("Threat assessment") {
        ThreatAssessmentView(assessment: row.threats)
      }
      Section("Correct this decision") {
        CorrectionControls(corrections: corrections, activity: activity, row: row)
        CorrectionPrompts(corrections: corrections, row: row)
        if row.correctionUndone {
          Text("Correction undone; the recorded Mail action was not reversed.")
        }
        if let undo = shared.state.correctionUndo, undo.isAvailable(in: shared.state) {
          UndoCorrectionButton(corrections: corrections, undo: undo)
        }
        OperationStatusView(operation: corrections.decision, identifier: "correction.status")
      }
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
        DisclosureGroup("Decision details") { DecisionDiagnosticsView(row: row) }
      }
    }.formStyle(.grouped)
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

private struct ThreatAssessmentView: View {
  let assessment: ThreatAssessment?

  private var findings: [ThreatFinding] {
    assessment?.findings.filter { $0.status == .detected } ?? []
  }

  var body: some View {
    if assessment?.findings.contains(where: { $0.status != .unknown }) != true {
      Text("Not assessed").foregroundStyle(.secondary)
        .accessibilityIdentifier("threats.status")
      Text("Mail placement does not establish message safety.")
    } else {
      if findings.isEmpty {
        Text("No threats detected within assessed coverage")
          .accessibilityIdentifier("threats.status")
      }
      ForEach(findings, id: \.kind) { finding in
        LabeledContent(finding.kind.localizedTitle, value: finding.reason)
      }
      DisclosureGroup("Assessment coverage") {
        ForEach(ThreatKind.allCases, id: \.self) { kind in
          LabeledContent(kind.localizedTitle) {
            if let finding = assessment?.finding(for: kind), finding.status != .unknown {
              Text(finding.coverage)
            } else {
              Text("Not assessed")
            }
          }
        }
        if let detector = assessment?.detector {
          LabeledContent("Detector", value: detector.implementation)
          LabeledContent("Model", value: detector.model)
        }
        Text("Findings describe assessed content only. Scores are not calibrated probabilities.")
      }
    }
  }
}

private extension ThreatKind {
  var localizedTitle: String {
    switch self {
      case .spam: String(localized: "Spam")
      case .phishing: String(localized: "Phishing")
      case .spearphishing: String(localized: "Spearphishing")
      case .fraud: String(localized: "Fraud")
      case .malware: String(localized: "Malware")
    }
  }
}

private struct CorrectionControls: View {
  let corrections: CorrectionsModel
  let activity: ActivityModel
  let row: DecisionRecord

  private var canCorrect: Bool {
    !corrections.decision.isBusy && row.path != .verification && row.sender != nil
  }

  var body: some View {
    HStack {
      ControlGroup {
        Button("Good") { corrections.correct(row, label: .inbox) }
          .accessibilityLabel("Mark as Good").accessibilityIdentifier("correction.good")
        Button("Junk") { corrections.correct(row, label: .junk) }
          .accessibilityLabel("Mark as Junk").accessibilityIdentifier("correction.junk")
        Button("Review") { corrections.correct(row, label: .review) }
          .accessibilityLabel("Mark as Review").accessibilityIdentifier("correction.review")
      }.disabled(!canCorrect)
      if corrections.decision.isBusy { ProgressView().controlSize(.small) }
    }
    if row.sender == nil {
      Text(
        "Corrections need the sender’s address, which this message doesn’t have. Move it in Mail instead."
      )
    }
    if let correction = row.correctedLabel {
      Text("User corrected to \(correction.localizedTitle)")
        .accessibilityIdentifier("correction.label").accessibilityValue(correction.rawValue)
    }
    HStack {
      DomainCorrectionMenu(corrections: corrections, activity: activity, row: row)
        .disabled(!canCorrect || row.evidence?.fromDomain == nil)
      Spacer()
      HelpButton(page: "correcting-mistakes")
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
          "\(domain) is a shared mail provider, so this rule also applies to unrelated people who use it. Known senders at this domain: \(knownSenders, format: .number)"
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

  private var evidenceDescription: String? {
    guard let evidence = row.evidence, let data = try? JSONEncoder.pretty.encode(evidence) else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  var body: some View {
    LabeledContent("Path", value: row.path.localizedTitle)
    LabeledContent("Policy revision", value: row.revision.formatted())
    LabeledContent("Account", value: row.identity.accountID ?? String(localized: "Unknown"))
    LabeledContent("Source mailbox", value: row.identity.mailbox ?? String(localized: "Unknown"))
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

struct VerdictBadge: View {
  let label: MailLabel?

  var body: some View {
    Text(label?.localizedTitle ?? String(localized: "Unclassified"))
      .accessibilityLabel("Verdict: \(label?.localizedTitle ?? String(localized: "Unclassified"))")
  }
}

#Preview("Decision") { DecisionDetailPreview(row: PreviewHelper.record) }
#Preview("Failed action") { DecisionDetailPreview(row: PreviewHelper.failedRecord) }
#Preview("Unclassified") { DecisionDetailPreview(row: PreviewHelper.unclassifiedRecord) }
#Preview("Verdict") { VerdictBadge(label: .review) }
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
#Preview("Diagnostics") { Form { DecisionDiagnosticsView(row: PreviewHelper.record) } }
#Preview("Unassessed threats") { Form { ThreatAssessmentView(assessment: nil) } }
#Preview("Threat finding") {
  Form { ThreatAssessmentView(assessment: PreviewHelper.threatAssessment) }
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
