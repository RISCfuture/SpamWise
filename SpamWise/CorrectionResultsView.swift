import SwiftUI
import SpamWiseCore

/// The progress and per-message results of correcting the messages selected in Mail.
struct CorrectionResultsView: View {
  let corrections: CorrectionsModel
  @Environment(\.dismiss)
  private var dismiss

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading) {
        if let batch = corrections.pendingSelection {
          UnverifiedSelectionPrompt(corrections: corrections, batch: batch)
        }
        if let progress = corrections.selectionProgress {
          ProgressView(value: Double(progress.completed), total: Double(progress.total)) {
            Text("Correcting \(progress.current) of \(progress.total)…")
          }
          .accessibilityIdentifier("corrections.progress")
        }
        List(corrections.selectionResults) { result in
          SelectionResultRow(corrections: corrections, result: result)
        }
        .overlay {
          if corrections.selection.isBusy, corrections.selectionResults.isEmpty,
            corrections.selectionProgress == nil
          {
            ProgressView()
          }
        }
        OperationStatusView(operation: corrections.selection, identifier: "corrections.status")
        OperationStatusView(operation: corrections.ruleRemoval)
      }
      .padding()
      .navigationTitle("Selected Message Corrections")
      .toolbar { CorrectionResultsToolbar(corrections: corrections, dismiss: dismiss) }
    }
    .frame(minWidth: 520, minHeight: 320)
  }
}

/// Done, which leaves a running batch going, and Cancel, which stops it.
private struct CorrectionResultsToolbar: ToolbarContent {
  let corrections: CorrectionsModel
  let dismiss: DismissAction

  var body: some ToolbarContent {
    if corrections.selection.isBusy {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") { corrections.cancelSelection() }
          .keyboardShortcut(.cancelAction)
          .accessibilityIdentifier("corrections.cancel")
      }
    }
    ToolbarItem(placement: .confirmationAction) {
      Button("Done") { dismiss() }
        .keyboardShortcut(.defaultAction)
        .accessibilityIdentifier("corrections.done")
    }
  }
}

/// Asks whether to block the selected senders SpamWise couldn’t verify.
private struct UnverifiedSelectionPrompt: View {
  let corrections: CorrectionsModel
  let batch: SelectionBatch

  var body: some View {
    UnverifiedSenderPrompt(
      message: String(
        localized:
          "SpamWise couldn’t verify the senders of \(batch.unverifiedIDs.count) of the \(batch.selectedCount) selected messages. If an address is forged, blocking it also sends the real sender’s mail to Junk."
      ),
      confirmTitle: "Block All",
      skipTitle: "Skip Unverified Senders",
      cancel: corrections.cancelPendingSelection,
      skip: { corrections.confirmPendingSelection(skippingUnverified: true) },
      confirm: { corrections.confirmPendingSelection(skippingUnverified: false) }
    )
  }
}

private struct SelectionResultRow: View {
  let corrections: CorrectionsModel
  let result: SelectionCorrectionResult

  var body: some View {
    VStack(alignment: .leading) {
      Text(result.message.displaySubject)
      switch result.outcome {
        case let .corrected(record, conflict):
          Text("Correction saved. Mail action: \(record.outcome.localizedTitle).")
            .foregroundStyle(.secondary)
          if let error = record.actionError { Text(error).foregroundStyle(.secondary) }
          if let conflict {
            RuleConflictPrompt(rule: conflict, keep: nil) {
              corrections.removeOverridingRule(conflict)
            }
          }
        case .skipped(let reason):
          Text(reason.localizedDescription).foregroundStyle(.secondary)
        case .failed(let description):
          Label(description, systemImage: "exclamationmark.triangle")
      }
    }
  }
}

#Preview("Correcting") {
  let model = PreviewHelper.model()
  model.corrections.preview(
    results: PreviewHelper.selectionResults,
    progress: CorrectionProgress(completed: 2, total: 6)
  )
  return CorrectionResultsView(corrections: model.corrections)
}
#Preview("Unverified senders") {
  let model = PreviewHelper.model()
  model.corrections.preview(results: [], pending: PreviewHelper.unverifiedSelection)
  return CorrectionResultsView(corrections: model.corrections)
}
#Preview("Finished") {
  let model = PreviewHelper.model()
  model.corrections.preview(results: PreviewHelper.selectionResults)
  return CorrectionResultsView(corrections: model.corrections)
}
