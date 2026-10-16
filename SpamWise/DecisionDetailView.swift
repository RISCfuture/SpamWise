import SwiftUI
import SpamWiseCore

struct DecisionDetailView: View {
  let model: AppModel
  let row: DecisionRecord

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
      }
      Section("Correct this decision") {
        CorrectionControls(model: model, row: row)
      }
      Section {
        DisclosureGroup("Decision details") { DecisionDiagnosticsView(row: row) }
      }
    }.formStyle(.grouped)
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
