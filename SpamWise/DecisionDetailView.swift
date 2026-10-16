import SwiftUI
import SpamWiseCore
import UniformTypeIdentifiers
import MailIntegration

struct DecisionDetailView: View {
  let model: AppModel
  let row: DecisionRecord
  @State private var source: RulesDocument?
  @State private var exporting = false
  @State private var confirmingUndo = false

  var body: some View {
    Form {
      Section {
        VStack(alignment: .leading) {
          Text(row.subject).font(.headline).textSelection(.enabled)
          Text(row.sender).foregroundStyle(.secondary).textSelection(.enabled)
        }
        VStack(alignment: .leading) {
          VerdictBadge(label: row.decision.label)
          Text(row.decision.reason).textSelection(.enabled)
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
        CorrectionControls(model: model, row: row)
        if row.correctionUndone == true {
          Text("Correction undone; the recorded Mail action was not reversed.")
        }
        if let undo = model.state.correctionUndo, undo.isAvailable(in: model.state) {
          Button("Undo latest correction…") { confirmingUndo = true }.disabled(model.busy)
            .accessibilityIdentifier("correction.undo")
            .confirmationDialog(
              "Restore the previous rules and learning? Mail will not move.",
              isPresented: $confirmingUndo
            ) {
              Button("Undo rules and learning") {
                model.run {
                  guard let store = model.store else { throw IntegrationError.unavailable }
                  try await CorrectionUndo.apply(store: store)
                  model.status = String(
                    localized:
                      "Correction undone. Use a separate correction to request a Mail action."
                  )
                }
              }.accessibilityIdentifier("correction.undo.confirm")
            } message: {
              Text(
                "Restores \(undo.ruleCount) rules and \(undo.exampleCount) examples. Later changes disable undo."
              )
            }
        }
      }
      Section {
        Button("Preview message") { model.previewMessage(row) }.disabled(model.busy)
        Button("Open in Mail") { model.openInMail(row) }.disabled(model.busy)
        Button("Export raw source…") {
          model.run {
            guard let envelope = try await model.adapter.lookup(row.identity) else {
              throw IntegrationError.unavailable
            }
            source = RulesDocument(data: envelope.raw); exporting = true
          }
        }.disabled(model.busy)
        DisclosureGroup("Decision details") { DecisionDiagnosticsView(row: row) }
      }
    }.formStyle(.grouped)
      .fileExporter(
        isPresented: $exporting,
        document: source,
        contentType: .data,
        defaultFilename: "message.eml"
      ) {
        if case .failure = $0 { model.status = String(localized: "Message source export failed.") }
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
  let model: AppModel
  let row: DecisionRecord

  var body: some View {
    ControlGroup {
      Button("Good") { model.correct(row, label: .inbox) }
        .accessibilityLabel("Mark as Good").accessibilityIdentifier("correction.good")
      Button("Junk") { model.correct(row, label: .junk) }
        .accessibilityLabel("Mark as Junk").accessibilityIdentifier("correction.junk")
      Button("Review") { model.correct(row, label: .review) }
        .accessibilityLabel("Mark as Review").accessibilityIdentifier("correction.review")
    }.disabled(model.busy || row.path == "verification")
    if let correction = row.correctedLabel {
      Text("User corrected to \(correction.localizedTitle)")
        .accessibilityIdentifier("correction.label").accessibilityValue(correction.rawValue)
    }
    HStack {
      Menu("Correct entire domain…") {
        Button("Allow this domain") { model.correct(row, label: .inbox, scope: .domain) }
          .accessibilityIdentifier("correction.domain.allow")
        Button("Block this domain") { model.correct(row, label: .junk, scope: .domain) }
          .accessibilityIdentifier("correction.domain.block")
      }.accessibilityIdentifier("correction.domain")
        .disabled(model.busy || row.evidence?.fromDomain == nil || row.path == "verification")
      Spacer()
      HelpButton(page: "correcting-mistakes")
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
    LabeledContent("Path", value: row.path)
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

#Preview("Decision") { DecisionDetailView(model: PreviewHelper.model(), row: PreviewHelper.record) }
#Preview("Failed action") {
  DecisionDetailView(model: PreviewHelper.model(), row: PreviewHelper.failedRecord)
}
#Preview("Verdict") { VerdictBadge(label: .review) }
#Preview("Corrections") {
  Form { CorrectionControls(model: PreviewHelper.model(), row: PreviewHelper.record) }
}
#Preview("Diagnostics") { Form { DecisionDiagnosticsView(row: PreviewHelper.record) } }
#Preview("Unassessed threats") { Form { ThreatAssessmentView(assessment: nil) } }
#Preview("Threat finding") {
  Form { ThreatAssessmentView(assessment: PreviewHelper.threatAssessment) }
}
