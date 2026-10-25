import SwiftUI
import SpamWiseCore

struct ContentView: View {
  /// The smallest Activity and setup window.
  static let minimumSize = CGSize(width: 720, height: 460)
  let model: AppModel

  var body: some View {
    Group {
      switch MainWindowContent(model.shared) {
        case .loading:
          ProgressView().controlSize(.large)
            .frame(minWidth: Self.minimumSize.width, minHeight: Self.minimumSize.height)
        case .recovery:
          StorageRecoveryView(recovery: model.recovery)
        case .unavailable, .newerVersion:
          StorageLoadingView(
            shared: model.shared,
            unavailableTitle: "SpamWise Data Unavailable",
            loadingTitle: "Loading…"
          )
          .frame(minWidth: Self.minimumSize.width, minHeight: Self.minimumSize.height)
        case .setup:
          OnboardingView(model: model)
        case .activity:
          ActivityView(model: model)
      }
    }
    .modifier(LoginLaunchWindow(router: model.router, shared: model.shared))
  }
}

/// What the main window shows, given what has been read from shared storage.
enum MainWindowContent: Equatable {
  /// The first read of shared storage is still running.
  case loading
  /// A newer version of SpamWise saved the data, so this version leaves it unread.
  case newerVersion
  /// Unreadable data was set aside and awaits a restore or a decision to keep the current state.
  case recovery
  /// Settings couldn't be read, so no screen shows defaults it would save over them.
  case unavailable
  /// First-run setup.
  case setup
  /// The Activity log.
  case activity

  @MainActor
  init(_ shared: SharedStateModel) {
    self =
      if !shared.hasLoadedState {
        .loading
      } else if shared.storedStateError == .newerVersion {
        .newerVersion
      } else if shared.needsRecovery {
        .recovery
      } else if !shared.hasLoadedSettings {
        .unavailable
      } else if !shared.settings.onboardingComplete {
        .setup
      } else {
        .activity
      }
  }
}

/// Closes the window macOS presents when it opens SpamWise at login, once setup is known finished.
private struct LoginLaunchWindow: ViewModifier {
  let router: ActivityRouter
  let shared: SharedStateModel
  @Environment(\.dismissWindow)
  private var dismissWindow

  private var isReady: Bool { router.closesWindowAtLogin && shared.hasLoadedState }

  func body(content: Content) -> some View {
    content.onChange(of: isReady, initial: true) { _, ready in
      guard ready else { return }
      router.closesWindowAtLogin = false
      if MainWindowContent(shared) == .activity { dismissWindow(id: "activity") }
    }
  }
}

private struct ActivityView: View {
  let model: AppModel
  @State private var selection: UUID?

  private var selected: DecisionRecord? { model.activity.record(id: selection) }
  private var reload: ActivityReload {
    ActivityReload(
      records: model.shared.recordsVersion,
      query: model.activity.queryRevision,
      limit: model.activity.visibleLimit
    )
  }

  var body: some View {
    @Bindable var activity = model.activity
    @Bindable var router = model.router
    VStack(spacing: 0) {
      if activity.query.hasFilters {
        ActivityFilterBanner(activity: activity)
      }
      ActivityTable(activity: activity, selection: $selection)
        .navigationTitle("Activity")
        .searchable(text: $activity.query.text, prompt: "Search sender, subject or reason")
        .toolbar(id: "activity") {
          ActivityToolbar(model: model, canInspect: selected != nil)
        }
        .inspector(isPresented: $router.showsInspector) {
          if let selected {
            DecisionDetailView(
              row: selected,
              corrections: model.corrections,
              messages: model.messages,
              shared: model.shared,
              activity: model.activity
            ) { model.router.present(.messagePreview($0)) }
            .inspectorColumnWidth(min: 300, ideal: 340, max: 440)
          }
        }
        .onChange(of: selection) { _, value in
          router.showsInspector = value != nil
          model.corrections.decision.status = nil
          model.messages.operation.status = nil
        }
      ActivityStatusView(model: model)
    }
    .frame(minWidth: ContentView.minimumSize.width, minHeight: ContentView.minimumSize.height)
    .focusedSceneValue(\.selectedDecision, selected)
    .task(id: reload) { await activity.reload() }
    .sheet(item: $router.sheet) { sheet in ActivitySheetView(sheet: sheet, model: model) }
  }
}

/// What the Activity table's contents depend on.
private struct ActivityReload: Equatable {
  let records: Int
  let query: Int
  let limit: Int
}

private struct ActivityTable: View {
  @Bindable var activity: ActivityModel
  @Binding var selection: UUID?

  var body: some View {
    Table(activity.rows, selection: $selection, sortOrder: $activity.sortOrder) {
      TableColumn("Date", value: \.date) { row in
        Text(row.date, format: .activityDate)
      }.width(min: 70, ideal: 120)
      TableColumn("Sender", value: \.displaySender).width(min: 120, ideal: 180)
      TableColumn("Subject", value: \.displaySubject) { row in
        Text(row.displaySubject).accessibilityIdentifier("activity.subject.\(row.id)")
      }.width(min: 160, ideal: 280)
      TableColumn("Verdict") { row in
        VerdictBadge(label: row.decision.label)
      }.width(min: 90, ideal: 110)
      TableColumn("Confidence") { row in
        if let verdict = row.verdict {
          Text(Double(verdict.confidence) / 100, format: .percent).monospacedDigit()
        }
      }.width(min: 60, ideal: 80)
      TableColumn("Reason") { row in
        let reason = row.decision.reason.localizedDescription
        Text(reason).lineLimit(1).help(reason)
      }.width(min: 120, ideal: 240)
    }
    .overlay {
      if activity.rows.isEmpty {
        ActivityEmptyView(filtered: activity.query.hasFilters || !activity.query.text.isEmpty)
      }
    }
    .safeAreaInset(edge: .bottom) {
      if activity.canShowMore {
        HStack {
          Text("Showing \(activity.rows.count) of \(activity.matchingCount)")
            .foregroundStyle(.secondary)
          Button("Show More") { activity.showMore() }
            .accessibilityIdentifier("activity.showMore")
        }
        .padding(.vertical, 6)
      }
    }
  }
}

private struct ActivityEmptyView: View {
  let filtered: Bool

  var body: some View {
    if filtered {
      ContentUnavailableView {
        Label("No matching decisions", systemImage: "line.3.horizontal.decrease.circle")
      } description: {
        Text("Change the search or clear the filters to see more.")
      }
    } else {
      ContentUnavailableView {
        Label("No decisions yet", systemImage: "tray")
      } description: {
        Text("Try a dry run to preview how your mail will be sorted.")
      }
    }
  }
}

/// Says that filters hide some decisions, with a way to show them all again.
private struct ActivityFilterBanner: View {
  let activity: ActivityModel

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Label(
          "Some decisions are hidden by filters.",
          systemImage: "line.3.horizontal.decrease.circle.fill"
        )
        .foregroundStyle(.secondary)
        Spacer()
        Button("Clear Filters") { activity.clearFilters() }
          .accessibilityIdentifier("activity.clearFilters")
      }
      .padding(.horizontal).padding(.vertical, 6)
      Divider()
    }
  }
}

private struct ActivityToolbar: CustomizableToolbarContent {
  let model: AppModel
  let canInspect: Bool

  var body: some CustomizableToolbarContent {
    ToolbarItem(id: "pause") {
      PauseFilteringButton(settings: model.settings, paused: model.shared.settings.paused)
        .accessibilityIdentifier("activity.pause")
    }
    ToolbarItem(id: "dryRun") {
      ActivityActionButton(action: .dryRun) { model.scanning.previewRecent() }
        .disabled(!model.services.storageReady)
        .accessibilityIdentifier("activity.scan")
    }
    ToolbarItem(id: "digest") {
      ActivityActionButton(action: .digest) { model.router.present(.digest) }
        .accessibilityIdentifier("activity.digest")
    }
    ToolbarItem(id: "junkReview") {
      ActivityActionButton(action: .junkReview) { model.router.present(.junkReview) }
        .accessibilityIdentifier("activity.junkReview")
    }
    ToolbarItem(id: "filter") {
      ActivityFilterMenu(activity: model.activity, shared: model.shared, router: model.router)
    }
    ToolbarItem(id: "statistics") {
      ActivityActionButton(action: .statistics) { model.router.present(.statistics) }
        .accessibilityIdentifier("activity.statistics")
    }
    ToolbarItem(id: "inspector", placement: .primaryAction) {
      InspectorToggle(router: model.router)
        .disabled(!canInspect)
        .accessibilityIdentifier("activity.inspector")
    }
  }
}

private struct ActivityFilterMenu: View {
  private static let outcomes: [ActionOutcome] = [
    .noAction, .dryRun, .paused, .pending, .requested, .applied, .failed, .unclassified,
    .superseded, .duplicate, .integrationUnavailable
  ]
  @Bindable var activity: ActivityModel
  let shared: SharedStateModel
  let router: ActivityRouter

  var body: some View {
    Menu {
      Picker("Account", selection: $activity.query.accountID) {
        Text("All accounts").tag(String?.none)
        ForEach(shared.activityAccounts, id: \.id) { account in
          Text(account.name).tag(Optional(account.id))
        }
      }
      Picker("Decided by", selection: $activity.query.path) {
        Text("All sources").tag(DecisionPath?.none)
        ForEach(DecisionPath.allCases, id: \.self) {
          Text($0.localizedTitle).tag(Optional($0))
        }
      }
      Picker("Outcome", selection: $activity.query.outcome) {
        Text("All outcomes").tag(ActionOutcome?.none)
        ForEach(Self.outcomes, id: \.self) { Text($0.localizedTitle).tag(Optional($0)) }
      }
      Toggle("Corrections only", isOn: $activity.query.correctionsOnly)
      Toggle("Today only", isOn: $activity.showsTodayOnly)
      Button("Date Range…") { router.present(.dateFilter) }
      Divider()
      Button("Clear Filters") { activity.clearFilters() }
        .disabled(!activity.query.hasFilters)
    } label: {
      Label(
        "Filter",
        systemImage: activity.query.hasFilters
          ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
      )
    }
    .help(activity.query.hasFilters ? "Filters are on" : "Show only some decisions")
    .accessibilityIdentifier("activity.filter")
  }
}

#Preview("Activity") { ContentView(model: PreviewHelper.model()) }
#Preview("Empty activity") { ContentView(model: PreviewHelper.model(empty: true)) }
#Preview("Paused") { ContentView(model: PreviewHelper.model(paused: true)) }
#Preview("Filtered") {
  let model = PreviewHelper.model()
  model.activity.query.outcome = .failed
  return ContentView(model: model)
}
#Preview("Activity table") { ActivityView(model: PreviewHelper.model()) }
