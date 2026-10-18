import SwiftUI
import SpamWiseCore

/// Setup's last step: a dry run of recent mail and what it decided.
struct SetupPreviewView: View {
  let scanning: ScanCoordinator
  let readiness: ClassifierReadiness
  let backend: ModelBackend
  /// Whether setup was completed before, so dry run is no longer forced on.
  let onboardingComplete: Bool
  /// Opens Activity; nil while Activity isn't available yet.
  let showActivity: (() -> Void)?

  var body: some View {
    Section("Try a dry run") {
      Text(
        "See what SpamWise would do with the \(ScanCoordinator.pageLimit) newest Inbox messages across your accounts. Nothing in Mail changes. Messages you’ve already previewed keep their result without a new request."
      )
      if backend.isCloud {
        Text(
          "Messages your rules can’t decide are sent to \(backend.localizedTitle) and may incur API charges."
        )
        .foregroundStyle(.secondary)
      }
      if !readiness.isReady {
        Text(
          """
          Your provider isn’t set up, so only your rules and known senders decide messages. The \
          rest stay unclassified.
          """
        )
        .foregroundStyle(.secondary)
      }
      HStack {
        Button("Dry run recent mail") { scanning.previewRecent() }
          .disabled(scanning.preview.isBusy)
          .accessibilityIdentifier("setup.dryRun")
        if scanning.preview.isBusy {
          ProgressView().controlSize(.small)
          Button("Stop Dry Run") { scanning.preview.cancel() }
        }
      }
      OperationStatusView(operation: scanning.preview, identifier: "setup.previewStatus")
    }
    if let preview = scanning.lastPreview {
      DryRunResultsView(
        summary: DryRunSummary(preview),
        backend: backend,
        showActivity: showActivity
      )
    }
    if !onboardingComplete {
      Section {
        Text(
          """
          Dry run stays on after setup. SpamWise records what it would do without changing mail \
          until you turn dry run off in Settings.
          """
        )
        .foregroundStyle(.secondary)
      }
    }
  }
}

/// The dry run's counts and one row per previewed message.
struct DryRunResultsView: View {
  let summary: DryRunSummary
  let backend: ModelBackend
  let showActivity: (() -> Void)?

  var body: some View {
    Section("Results") {
      if summary.isEmpty {
        Text("No recent Inbox mail to preview.").foregroundStyle(.secondary)
          .accessibilityIdentifier("setup.previewEmpty")
      } else {
        if let blocker = summary.blocker {
          StatusLabel(
            status: .failure(OperationFailure(message: blocker.explanation(for: backend))),
            identifier: "setup.previewBlocker"
          )
        }
        LabeledContent("Junk", value: summary.junk.formatted())
        LabeledContent("Review", value: summary.review.formatted())
        if summary.unreadable > 0 {
          LabeledContent("Couldn’t be read", value: summary.unreadable.formatted())
        }
        ForEach(summary.rows) { row in DryRunRowView(row: row) }
      }
      if let showActivity {
        Button("Show in Activity", action: showActivity)
      } else if !summary.isEmpty {
        Text("After setup, Activity shows each decision and why it was made.")
          .foregroundStyle(.secondary)
      }
    }
  }
}

/// One previewed message: its subject, sender and verdict.
private struct DryRunRowView: View {
  let row: DryRunSummary.Row

  var body: some View {
    LabeledContent {
      Text(row.verdict.localizedTitle)
    } label: {
      Text(row.subject ?? String(localized: "No subject")).lineLimit(1)
      Text(row.sender ?? String(localized: "Unknown sender")).lineLimit(1)
    }
  }
}

extension DryRunSummary.Verdict {
  fileprivate var localizedTitle: String {
    switch self {
      case .good: String(localized: "Good")
      case .junk: String(localized: "Junk")
      case .review: String(localized: "Review")
      case .notClassified: String(localized: "Not classified")
    }
  }
}

extension DryRunSummary.Blocker {
  fileprivate func explanation(for backend: ModelBackend) -> String {
    switch self {
      case .consentRequired:
        String(
          localized:
            "Some messages weren’t classified because mail sharing with \(backend.localizedTitle) is off. Go back to allow it or choose another provider."
        )
      case .missingKey:
        String(
          localized:
            "Some messages weren’t classified because no \(backend.localizedTitle) API key is saved. Go back to add one."
        )
      case .providerUnavailable:
        String(
          localized:
            "Some messages weren’t classified because the selected provider isn’t available. Go back to choose another."
        )
      case .spendingLimitReached:
        String(
          localized:
            "Some messages weren’t classified because this month’s spending limit was reached."
        )
    }
  }
}

#Preview("Before a dry run") {
  Form {
    SetupPreviewView(
      scanning: PreviewHelper.model().scanning,
      readiness: .ready,
      backend: .claude,
      onboardingComplete: false,
      showActivity: nil
    )
  }
  .formStyle(.grouped)
}
#Preview("Results") {
  Form {
    DryRunResultsView(
      summary: DryRunSummary(PreviewHelper.dryRun()),
      backend: .claude,
      showActivity: {}
    )
  }
  .formStyle(.grouped)
}
#Preview("Consent off") {
  Form {
    DryRunResultsView(
      summary: DryRunSummary(PreviewHelper.dryRun(consentRequired: true)),
      backend: .gemini,
      showActivity: nil
    )
  }
  .formStyle(.grouped)
}
#Preview("No mail") {
  Form {
    DryRunResultsView(
      summary: DryRunSummary(MailPreview(records: [], unavailableCount: 0)),
      backend: .onDevice,
      showActivity: nil
    )
  }
  .formStyle(.grouped)
}
