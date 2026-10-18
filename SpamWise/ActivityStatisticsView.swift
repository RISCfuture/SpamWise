import SwiftUI
import Charts
import UniformTypeIdentifiers
import SpamWiseCore

struct ActivityStatisticsView: View {
  let activity: ActivityModel
  let shared: SharedStateModel
  @State private var start = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
  @State private var end = Date.now
  @State private var account: String?
  @State private var statistics: ActivityStatistics?
  @State private var status: OperationStatus?
  @State private var export: RulesDocument?
  @State private var showsExport = false
  @Environment(\.dismiss) private var dismiss

  private var query: ActivityQuery {
    var query = ActivityQuery()
    query.start = Calendar.current.startOfDay(for: start)
    let followingDay = Calendar.current.date(
      byAdding: .day,
      value: 1,
      to: Calendar.current.startOfDay(for: end)
    )
    query.end = followingDay?.addingTimeInterval(-0.001)
    query.accountID = account
    return query
  }
  private var reload: StatisticsReload {
    StatisticsReload(start: start, end: end, account: account, records: shared.recordsVersion)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          DatePicker("From", selection: $start, displayedComponents: .date)
          DatePicker("Through", selection: $end, displayedComponents: .date)
          Picker("Account", selection: $account) {
            Text("All accounts").tag(String?.none)
            ForEach(shared.knownAccounts, id: \.id) { account in
              Text(account.name).tag(Optional(account.id))
            }
          }
          if let statistics {
            StatisticsCounts(statistics: statistics)
          } else {
            ProgressView()
          }
          Text("Retained log only. Selective corrections do not measure accuracy or calibration.")
            .foregroundStyle(.secondary)
        }
        if let statistics {
          Section("Decisions per day") {
            Chart(statistics.dailyCounts.keys.sorted(), id: \.self) { day in
              BarMark(
                x: .value("Day", day, unit: .day),
                y: .value("Decisions", statistics.dailyCounts[day] ?? 0)
              )
            }.frame(height: 140).accessibilityLabel("Daily decision counts")
          }
        }
        Section {
          HStack {
            Button("Export statistics") { exportStatistics() }.disabled(statistics == nil)
            Button("Export redacted diagnostics") { exportDiagnostics() }
          }
          StatusLabel(status: status)
        }
      }
      .formStyle(.grouped)
      .navigationTitle("Activity statistics")
      .toolbar { DoneToolbarItem(dismiss: dismiss, identifier: "statistics.done") }
    }
    .frame(minWidth: 600, minHeight: 600)
    .task(id: reload) { await load() }
    .fileExporter(
      isPresented: $showsExport,
      document: export,
      contentType: .json,
      defaultFilename: "SpamWise-report"
    ) { status = ExportResult.status(of: $0, failure: "Report export failed.") }
  }

  private func load() async {
    do {
      statistics = ActivityStatistics(records: try await activity.records(matching: query))
      status = nil
    } catch {
      status = .failure(OperationFailure(error))
    }
  }

  private func exportStatistics() {
    guard let statistics, let data = try? JSONEncoder.pretty.encode(statistics) else { return }
    export = RulesDocument(data: data); showsExport = true
  }

  private func exportDiagnostics() {
    Task {
      do {
        export = RulesDocument(data: try await activity.diagnostics()); showsExport = true
      } catch {
        status = .failure(OperationFailure(error))
      }
    }
  }
}

/// What the shown statistics depend on.
private struct StatisticsReload: Equatable {
  let start: Date
  let end: Date
  let account: String?
  let records: Int
}

private struct StatisticsCounts: View {
  let statistics: ActivityStatistics

  var body: some View {
    LabeledContent("Decisions") {
      Text(statistics.decisions.formatted()).accessibilityIdentifier("statistics.decisions")
    }
    LabeledContent("Unresolved Review", value: statistics.unresolvedReview.formatted())
    LabeledContent("Action failures", value: statistics.actionFailures.formatted())
    LabeledContent("Reviewed decisions", value: statistics.reviewedDecisions.formatted())
    LabeledContent("Reviewed disagreements", value: statistics.reviewedMistakes.formatted())
    LabeledContent(
      "Estimated cost",
      value: statistics.estimatedCostUSD.formatted(.currency(code: "USD"))
    )
  }
}

#Preview("Activity statistics") {
  let model = PreviewHelper.model()
  ActivityStatisticsView(activity: model.activity, shared: model.shared)
}
#Preview("Empty statistics") {
  let model = PreviewHelper.model(empty: true)
  ActivityStatisticsView(activity: model.activity, shared: model.shared)
}
