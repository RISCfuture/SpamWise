import SwiftUI
import SpamWiseCore

struct ContentView: View {
  let model: AppModel

  var body: some View {
    Group {
      if !model.shared.hasLoadedState {
        ProgressView().controlSize(.large)
          .frame(minWidth: 720, minHeight: 460)
      } else if !model.shared.settings.onboardingComplete {
        OnboardingView(model: model)
      } else {
        ActivityView(model: model)
      }
    }
  }
}

private struct ActivityView: View {
  let model: AppModel
  @State private var selection: UUID?
  @State private var showsInspector = false

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
      ActivityTable(activity: activity, selection: $selection)
        .navigationTitle("Activity")
        .searchable(text: $activity.query.text, prompt: "Search sender, subject or reason")
        .toolbar {
          ActivityToolbar(
            model: model,
            showsInspector: $showsInspector,
            canInspect: selected != nil
          )
        }
        .inspector(isPresented: $showsInspector) {
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
          showsInspector = value != nil
          model.corrections.decision.status = nil
          model.messages.operation.status = nil
        }
      ActivityStatusView(model: model)
    }
    .frame(minWidth: 720, minHeight: 460)
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
  let activity: ActivityModel
  @Binding var selection: UUID?

  var body: some View {
    Table(activity.rows, selection: $selection) {
      TableColumn("Time") { row in
        Text(row.date, format: .dateTime.hour().minute())
      }.width(min: 60, ideal: 75)
      TableColumn("Sender") { row in Text(row.displaySender) }.width(min: 120, ideal: 180)
      TableColumn("Subject") { row in
        Text(row.displaySubject).accessibilityIdentifier("activity.subject.\(row.id)")
      }.width(min: 160, ideal: 320)
      TableColumn("Verdict") { row in
        VerdictBadge(label: row.decision.label)
      }.width(min: 90, ideal: 110)
    }
    .overlay {
      if activity.rows.isEmpty {
        ContentUnavailableView {
          Label("No decisions yet", systemImage: "tray")
        } description: {
          Text("Try a dry run to preview how your mail will be classified.")
        }
      }
    }
    .safeAreaInset(edge: .bottom) {
      if activity.canShowMore {
        HStack {
          Text(
            "Showing \(activity.rows.count, format: .number) of \(activity.matchingCount, format: .number)"
          )
          .foregroundStyle(.secondary)
          Button("Show More") { activity.showMore() }
            .accessibilityIdentifier("activity.showMore")
        }
        .padding(.vertical, 6)
      }
    }
  }
}

private struct ActivityToolbar: ToolbarContent {
  let model: AppModel
  @Binding var showsInspector: Bool
  let canInspect: Bool

  var body: some ToolbarContent {
    ToolbarItemGroup {
      Button(model.shared.settings.paused ? "Resume filtering" : "Pause filtering") {
        model.settings.togglePause()
      }.accessibilityIdentifier("activity.pause")
      Button("Dry run recent mail") { model.scanning.previewRecent() }
        .disabled(!model.services.storageReady)
        .accessibilityIdentifier("activity.scan")
      Button("Review digest") { model.router.present(.digest) }
        .accessibilityIdentifier("activity.digest")
      Button("Review Junk") { model.router.present(.junkReview) }
    }
    ToolbarItem {
      ActivityFilterMenu(activity: model.activity, shared: model.shared, router: model.router)
    }
    ToolbarItem {
      Button("Statistics") { model.router.present(.statistics) }
        .accessibilityIdentifier("activity.statistics")
    }
    ToolbarItem {
      Button("Show details", systemImage: "sidebar.right") { showsInspector.toggle() }
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
    Menu("Filter") {
      Picker("Account", selection: $activity.query.accountID) {
        Text("All accounts").tag(String?.none)
        ForEach(shared.knownAccounts, id: \.id) { account in
          Text(account.name).tag(Optional(account.id))
        }
      }
      Picker("Path", selection: $activity.query.path) {
        Text("All paths").tag(DecisionPath?.none)
        ForEach(DecisionPath.allCases, id: \.self) {
          Text($0.localizedTitle).tag(Optional($0))
        }
      }
      Picker("Outcome", selection: $activity.query.outcome) {
        Text("All outcomes").tag(ActionOutcome?.none)
        ForEach(Self.outcomes, id: \.self) { Text($0.localizedTitle).tag(Optional($0)) }
      }
      Toggle("Corrections only", isOn: $activity.query.correctionsOnly)
      Button("Today") {
        activity.query.start = Calendar.current.startOfDay(for: .now); activity.query.end = nil
      }
      Button("Date range…") { router.present(.dateFilter) }
      Button("Clear filters") { activity.query = ActivityQuery() }
    }.accessibilityIdentifier("activity.filter")
  }
}

#Preview("Activity") { ContentView(model: PreviewHelper.model()) }
#Preview("Empty activity") { ContentView(model: PreviewHelper.model(empty: true)) }
#Preview("Paused") { ContentView(model: PreviewHelper.model(paused: true)) }
#Preview("Activity table") { ActivityView(model: PreviewHelper.model()) }
