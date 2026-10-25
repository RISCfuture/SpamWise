import SwiftUI
import SpamWiseCore

/// The Activity footer: filtering mode, leaving dry run, checks, announcements and today’s totals.
struct ActivityStatusView: View {
  let model: AppModel
  @Environment(\.openSettings)
  private var openSettings

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Divider()
      HStack {
        FilteringStateView(state: model.scanning.filteringState)
        LeaveDryRunButton(
          state: model.scanning.filteringState,
          transport: model.shared.settings.advancedOptions.transport,
          canStartFiltering: model.router.canConfirmLiveFiltering
        ) {
          model.router.confirmLiveFiltering()
        } checkConnection: {
          showConnectionCheck(preferences: model.services.preferences, openSettings: openSettings)
        }
        BackgroundCheckView(scanning: model.scanning)
        Spacer()
        TodayTotalsView(
          today: model.activity.today,
          monthCost: model.shared.monthCost,
          backend: model.shared.settings.advancedOptions.backend
        )
      }
      if let digest = model.shared.pendingDigest {
        DigestAnnouncementView(count: digest.records.count) { model.router.present(.digest) }
      }
      if model.shared.spendingLimitReached {
        WarningLabel(
          "Monthly spending limit reached — new mail isn’t sent to the provider until next month or a higher limit."
        )
        .accessibilityIdentifier("activity.spendingLimit")
      }
      MissingProviderKeyBanner(
        credentials: model.credentials,
        backend: model.shared.settings.advancedOptions.backend
      )
      StatusLabel(status: model.shared.storageStatus)
      StatusLabel(status: model.activity.loadFailure.map(OperationStatus.failure))
      StatusLabel(status: model.notifications.deliveryFailure.map(OperationStatus.failure))
      StatusLabel(status: model.backgroundFailure.map(OperationStatus.failure))
      StatusLabel(status: model.scanning.sweepStatus, identifier: "activity.sweepStatus")
      OperationStatusView(operation: model.scanning.preview, identifier: "activity.previewStatus")
    }
    .font(.callout)
    .padding(.horizontal).padding(.bottom, 8)
  }
}

/// The aggregate filtering state, marked when it needs attention.
private struct FilteringStateView: View {
  let state: FilteringState

  var body: some View {
    Group {
      if state.needsAttention {
        Label(state.localizedTitle, systemImage: "exclamationmark.triangle")
      } else {
        Text(state.localizedTitle)
      }
    }
    .accessibilityIdentifier("activity.mode.\(state.rawValue)")
  }
}

/// Progress of the automatic check and the user's dry run, each with its own Stop button.
private struct BackgroundCheckView: View {
  let scanning: ScanCoordinator

  var body: some View {
    if let progress = scanning.progress {
      ProgressView { Text("Checking mail…") }.labelsHidden().controlSize(.small)
      if progress.total > 0 {
        Text("Checking mail… \(progress.processed) of \(progress.total)")
          .foregroundStyle(.secondary)
      } else {
        Text("Checking mail…").foregroundStyle(.secondary)
      }
      Button("Stop") { scanning.stop() }
        .help("Stops this check. The next one starts in \(ScanCoordinator.intervalText).")
    } else if let date = scanning.lastCompletion {
      Text("Last checked \(date, format: .activityDate)").foregroundStyle(.secondary)
    }
    if scanning.preview.isBusy {
      ProgressView { Text("Running dry run…") }.labelsHidden().controlSize(.small)
      Text("Running dry run…").foregroundStyle(.secondary)
      Button("Stop Dry Run") { scanning.preview.cancel() }
    }
  }
}

/// Today's counts, and this month's estimated cost for a provider that charges for its API.
private struct TodayTotalsView: View {
  let today: TodaySummary
  let monthCost: Double
  let backend: ModelBackend

  var body: some View {
    Text("Today: \(today.decisions) messages, \(today.junk) Junk, \(today.review) Review")
      .foregroundStyle(.secondary)
      .accessibilityIdentifier("activity.today")
    if backend.requiresAPIKey {
      Text("Estimated cost this month: \(EstimatedCost.formatted(monthCost))")
        .foregroundStyle(.secondary)
    }
  }
}

/// Announces this week's digest without presenting it.
private struct DigestAnnouncementView: View {
  let count: Int
  let open: () -> Void

  var body: some View {
    HStack {
      Label(
        "This week’s Review digest is ready: \(count) messages",
        systemImage: "tray.full"
      )
      Button("Open Digest", action: open).accessibilityIdentifier("activity.openDigest")
    }
  }
}

#Preview("Activity status") { ActivityStatusView(model: PreviewHelper.model()) }
#Preview("Spending limit reached") {
  ActivityStatusView(model: PreviewHelper.model(spendingLimitReached: true))
}
#Preview("Filtering states") {
  VStack(alignment: .leading) {
    ForEach(FilteringState.allCases, id: \.self) { FilteringStateView(state: $0) }
  }.padding()
}
#Preview("Digest announcement") {
  DigestAnnouncementView(count: 3) {}.padding()
}
