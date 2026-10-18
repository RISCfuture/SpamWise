import SwiftUI
import SpamWiseCore

/**
 The menu bar’s corrections for the messages selected in Mail.

 Corrections run without bringing Activity forward: the menu shows their progress and outcome,
 and opens the results only when the user asks or a choice is needed.
 */
struct SelectionCorrectionMenu: View {
  let corrections: CorrectionsModel
  let canActOnMail: Bool
  /// Shows a sheet in the Activity window.
  let show: (ActivitySheet) -> Void

  private var canCorrect: Bool {
    canActOnMail && !corrections.selection.isBusy && corrections.pendingSelection == nil
  }

  var body: some View {
    Section("Selected messages in Mail") {
      SelectionCorrectionStatus(corrections: corrections, show: show)
      Group {
        Button("Mark as Good") { correct(.inbox) }
          .keyboardShortcut("g", modifiers: [.command, .option])
        Button("Mark as Junk") { correct(.junk) }
          .keyboardShortcut("j", modifiers: [.command, .option])
        Button("Mark for Review") { correct(.review) }
          .keyboardShortcut("r", modifiers: [.command, .option])
        Menu("Correct Senders’ Domains") {
          Button("Allow Senders’ Domains") { correct(.inbox, scope: .domain) }
          Button("Block Senders’ Domains") { correct(.junk, scope: .domain) }
        }
      }
      .disabled(!canCorrect)
    }
  }

  private func correct(_ label: MailLabel, scope: RuleScope = .address) {
    corrections.correctSelection(label, scope: scope) { show(.selectionCorrections) }
  }
}

/// The running or latest selected-message correction, as menu items.
private struct SelectionCorrectionStatus: View {
  let corrections: CorrectionsModel
  let show: (ActivitySheet) -> Void

  var body: some View {
    if let progress = corrections.selectionProgress {
      Text("Correcting \(progress.current) of \(progress.total)…")
      Button("Stop Correcting") { corrections.cancelSelection() }
    } else if corrections.pendingSelection != nil {
      Button("Confirm Unverified Senders…") { show(.selectionCorrections) }
    } else if let summary = corrections.selectionSummary {
      Text(summary)
      Button("Show Correction Results…") { show(.selectionCorrections) }
    }
  }
}
