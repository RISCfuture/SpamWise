import SwiftUI
import Charts
import UniformTypeIdentifiers
import SpamWiseCore

struct ActivityStatisticsView: View {
  /// Days before today that the statistics cover when the sheet opens.
  private static let defaultRangeDays = 30
  let activity: ActivityModel
  let shared: SharedStateModel
  @State private var start =
    Calendar.current.date(byAdding: .day, value: -Self.defaultRangeDays, to: .now)
    ?? .now
  @State private var end = Date.now
  @State private var account: String?
  @State private var statistics: ActivityStatistics?
  @State private var status: OperationStatus?
  @State private var export: RulesDocument?
  @State private var showsExport = false
  @Environment(\.dismiss)
  private var dismiss

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
            ForEach(shared.activityAccounts, id: \.id) { account in
              Text(account.name).tag(Optional(account.id))
            }
          }
          if let statistics {
            StatisticsCounts(statistics: statistics)
          } else {
            ProgressView()
          }
        }
        if let statistics {
          Section("Messages per day") {
            DailyAccountChart(points: DailyAccountCount.points(statistics, shared: shared))
          }
        }
        Section {
          HStack {
            Button("Export Statistics…") { exportStatistics() }.disabled(statistics == nil)
            Button("Export Redacted Diagnostics…") { exportDiagnostics() }
            Spacer()
            HelpButton(page: "statistics")
          }
          StatusLabel(status: status)
        }
      }
      .formStyle(.grouped)
      .navigationTitle("Activity Statistics")
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
      let records = try await activity.records(matching: query)
      statistics = ActivityStatistics(records: records.filter { $0.path != .verification })
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

/// One account's decisions on one day, labeled by the account's name.
struct DailyAccountCount: Identifiable {
  let account: String
  let day: Date
  let count: Int
  var id: String { "\(account)|\(day.timeIntervalSinceReferenceDate)" }

  /// Every account's daily counts, named for display and ordered by day.
  @MainActor
  static func points(_ statistics: ActivityStatistics, shared: SharedStateModel)
    -> [Self]
  {
    statistics.accountDailyCounts.flatMap { account, days in
      let name = shared.accountName(
        for: account == ActivityStatistics.unknownAccount ? nil : account
      )
      return days.map { Self(account: name, day: $0.key, count: $0.value) }
    }
    .sorted { $0.day < $1.day }
  }
}

private struct DailyAccountChart: View {
  let points: [DailyAccountCount]

  var body: some View {
    Chart(points) { point in
      BarMark(
        x: .value("Day", point.day, unit: .day),
        y: .value("Messages", point.count)
      )
      .foregroundStyle(by: .value("Account", point.account))
    }
    .frame(height: 160)
    .accessibilityLabel("Messages per day by account")
  }
}

private struct StatisticsCounts: View {
  let statistics: ActivityStatistics

  var body: some View {
    LabeledContent("Messages") {
      Text(statistics.decisions.formatted()).accessibilityIdentifier("statistics.decisions")
    }
    LabeledContent("Waiting for Review", value: statistics.unresolvedReview.formatted())
    LabeledContent("Mail actions that failed", value: statistics.actionFailures.formatted())
    LabeledContent("Decisions you reviewed", value: statistics.reviewedDecisions.formatted())
    ReviewedDisagreementsView(statistics: statistics)
    LabeledContent(
      "Estimated cost",
      value: statistics.estimatedCostUSD.formatted(.currency(code: "USD"))
    )
  }
}

/// How many reviewed decisions you changed, with the most that share could be.
private struct ReviewedDisagreementsView: View {
  let statistics: ActivityStatistics

  var body: some View {
    LabeledContent("Decisions you changed") {
      VStack(alignment: .trailing) {
        Text("\(statistics.reviewedMistakes) of \(statistics.reviewedDecisions)")
        if let bound = statistics.reviewedMistakeUpperBound {
          Text(
            "At most \(bound, format: .percent.precision(.fractionLength(0...1))) of reviewed decisions"
          )
          .foregroundStyle(.secondary)
        }
      }
    }
    .help("With 95% confidence, at most this share of the decisions you reviewed needed a change.")
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
#Preview("Reviewed counts") {
  Form {
    StatisticsCounts(
      statistics: ActivityStatistics(
        records: [PreviewHelper.correctedRecord, PreviewHelper.record]
      )
    )
  }
}
