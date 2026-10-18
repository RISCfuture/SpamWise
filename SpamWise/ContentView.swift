import SwiftUI
import SpamWiseCore

struct ContentView: View {
  let model: AppModel

  var body: some View {
    Group {
      if !model.hasLoadedState {
        ProgressView().controlSize(.large)
          .frame(minWidth: 720, minHeight: 460)
      } else if !model.state.settings.onboardingComplete {
        OnboardingView(model: model)
      } else {
        ActivityView(model: model)
      }
    }
  }
}

private struct ActivityView: View {
  @Bindable var model: AppModel
  @State private var selection: UUID?
  @State private var showsInspector = false
  @State private var query = ActivityQuery()
  @State private var showsStatistics = false
  @State private var showsDates = false

  private var selected: DecisionRecord? {
    model.state.records.first { $0.id == selection }
  }

  var body: some View {
    VStack(spacing: 0) {
      Table(query.apply(to: model.state.records), selection: $selection) {
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
        if model.state.records.isEmpty {
          ContentUnavailableView {
            Label("No decisions yet", systemImage: "tray")
          } description: {
            Text("Try a dry run to preview how your mail will be classified.")
          }
        }
      }
      .navigationTitle("Activity")
      .searchable(text: $query.text, prompt: "Search sender, subject or reason")
      .toolbar {
        ToolbarItemGroup {
          Button(model.state.settings.paused ? "Resume filtering" : "Pause filtering") {
            model.togglePause()
          }.accessibilityIdentifier("activity.pause")
          Button("Dry run recent mail") { model.scan() }
            .disabled(model.busy || !model.storageReady)
            .accessibilityIdentifier("activity.scan")
          Button("Review digest") { model.showDigest = true }
            .accessibilityIdentifier("activity.digest")
          Button("Review Junk") {
            model.showJunk = true
            model.run { try await model.discoverAccounts() }
          }.disabled(model.busy)
        }
        ToolbarItem {
          Menu("Filter") {
            Picker("Account", selection: $query.accountID) {
              Text("All accounts").tag(String?.none)
              ForEach(
                Array(Set(model.state.records.compactMap { $0.identity.accountID })).sorted(),
                id: \.self
              ) {
                Text($0).tag(Optional($0))
              }
            }
            Picker("Path", selection: $query.path) {
              Text("All paths").tag(DecisionPath?.none)
              ForEach(
                DecisionPath.allCases.filter(Set(model.state.records.map(\.path)).contains),
                id: \.self
              ) {
                Text($0.localizedTitle).tag(Optional($0))
              }
            }
            Picker("Outcome", selection: $query.outcome) {
              Text("All outcomes").tag(ActionOutcome?.none)
              ForEach(
                Array(Set(model.state.records.map { $0.outcome.rawValue })).sorted(),
                id: \.self
              ) { value in
                if let outcome = ActionOutcome(rawValue: value) {
                  Text(outcome.localizedTitle).tag(Optional(outcome))
                }
              }
            }
            Toggle("Corrections only", isOn: $query.correctionsOnly)
            Button("Today") {
              query.start = Calendar.current.startOfDay(for: .now); query.end = nil
            }
            Button("Date range…") { showsDates = true }
            Button("Clear filters") { query = ActivityQuery() }
          }.accessibilityIdentifier("activity.filter")
        }
        ToolbarItem {
          Button("Statistics") { showsStatistics = true }
            .accessibilityIdentifier("activity.statistics")
        }
        ToolbarItem {
          Button("Show details", systemImage: "sidebar.right") { showsInspector.toggle() }
            .disabled(selected == nil)
            .accessibilityIdentifier("activity.inspector")
        }
      }
      .inspector(isPresented: $showsInspector) {
        if let selected {
          DecisionDetailView(model: model, row: selected)
            .inspectorColumnWidth(min: 300, ideal: 340, max: 440)
        }
      }
      .onChange(of: selection) { _, value in showsInspector = value != nil }
      ActivityStatusView(model: model)
    }
    .frame(minWidth: 720, minHeight: 460)
    .sheet(isPresented: $model.showDigest) { ReviewDigestView(model: model) }
    .sheet(isPresented: $model.showCorrections) { CorrectionResultsView(model: model) }
    .sheet(isPresented: $model.showJunk) { MailReviewView(model: model) }
    .sheet(isPresented: $model.showPreview) { MessagePreviewView(text: model.previewText) }
    .sheet(isPresented: $showsStatistics) { ActivityStatisticsView(model: model) }
    .sheet(isPresented: $model.showAudit) { AuditTrailView(model: model) }
    .sheet(isPresented: $model.showCorpus) { CorpusView(model: model) }
    .sheet(isPresented: $showsDates) { ActivityDateFilterView(query: $query) }
  }
}

private struct ActivityStatusView: View {
  let model: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Divider()
      HStack {
        Text(model.filteringStatus.localizedTitle).accessibilityIdentifier("activity.mode")
          .accessibilityValue(model.filteringStatus.rawValue)
        if model.busy {
          ProgressView().controlSize(.small)
          Button("Cancel") { model.cancel() }
        }
        Spacer()
        Text("Today: \(model.today.count, format: .number)")
          .help(
            "Decisions today: \(model.today.count, format: .number) · Junk: \(model.today.filter { $0.decision.label == .junk }.count, format: .number) · Review: \(model.today.filter { $0.decision.label == .review }.count, format: .number)"
          )
        Text("Month: \(model.monthCost, format: .currency(code: "USD"))")
          .help("Estimated API cost this month")
      }
      if model.spendingLimitReached {
        Text(
          "Monthly spending limit reached — new mail isn’t sent to the provider until next month or a higher limit."
        )
        .foregroundStyle(.primary)
        .accessibilityIdentifier("activity.spendingLimit")
      }
      if !model.status.isEmpty {
        Text(model.status).textSelection(.enabled).accessibilityIdentifier("activity.status")
          .lineLimit(2)
      }
    }
    .font(.callout).foregroundStyle(.secondary)
    .padding(.horizontal).padding(.bottom, 8)
  }
}

#Preview("Activity") { ContentView(model: PreviewHelper.model()) }
#Preview("Empty activity") { ContentView(model: PreviewHelper.model(empty: true)) }
#Preview("Paused") { ContentView(model: PreviewHelper.model(paused: true)) }

#Preview("Activity status") { ActivityStatusView(model: PreviewHelper.model()) }
#Preview("Spending limit reached") {
  ActivityStatusView(model: PreviewHelper.model(spendingLimitReached: true))
}

#Preview("Activity table") { ActivityView(model: PreviewHelper.model()) }
