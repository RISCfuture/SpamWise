import SwiftUI
import Charts
import UniformTypeIdentifiers
import SpamWiseCore

struct ActivityStatisticsView: View {
  let model: AppModel
  @State private var start = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
  @State private var end = Date.now
  @State private var account: String?
  @State private var export: RulesDocument?
  @State private var showsExport = false
  @Environment(\.dismiss) private var dismiss

  private var statistics: ActivityStatistics {
    var query = ActivityQuery()
    query.start = Calendar.current.startOfDay(for: start)
    let followingDay = Calendar.current.date(
      byAdding: .day,
      value: 1,
      to: Calendar.current.startOfDay(for: end)
    )
    query.end = followingDay?.addingTimeInterval(-0.001)
    query.accountID = account
    return ActivityStatistics(records: query.apply(to: model.state.records))
  }

  var body: some View {
    VStack {
      Form {
        Section("Activity statistics") {
          DatePicker("From", selection: $start, displayedComponents: .date)
          DatePicker("Through", selection: $end, displayedComponents: .date)
          Picker("Account", selection: $account) {
            Text("All accounts").tag(String?.none)
            ForEach(
              Array(Set(model.state.records.compactMap { $0.identity.accountID })).sorted(),
              id: \.self
            ) {
              Text($0).tag(Optional($0))
            }
          }
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
          Text("Retained log only. Selective corrections do not measure accuracy or calibration.")
            .foregroundStyle(.secondary)
        }
        Section("Decisions per day") {
          Chart(statistics.dailyCounts.keys.sorted(), id: \.self) { day in
            BarMark(
              x: .value("Day", day, unit: .day),
              y: .value("Decisions", statistics.dailyCounts[day] ?? 0)
            )
          }.frame(height: 140).accessibilityLabel("Daily decision counts")
        }
      }.formStyle(.grouped)
      HStack {
        Button("Export statistics") {
          if let data = try? JSONEncoder.pretty.encode(statistics) {
            export = RulesDocument(data: data); showsExport = true
          }
        }
        Button("Export redacted diagnostics") {
          if let data = try? JSONEncoder.pretty.encode(DiagnosticSummary(state: model.state)) {
            export = RulesDocument(data: data); showsExport = true
          }
        }
        Spacer()
        Button("Done") { dismiss() }.accessibilityIdentifier("statistics.done")
      }.padding()
    }.frame(minWidth: 600, minHeight: 600)
      .fileExporter(
        isPresented: $showsExport,
        document: export,
        contentType: .json,
        defaultFilename: "SpamWise-report"
      ) {
        if case .failure = $0 { model.status = String(localized: "Report export failed.") }
      }
  }
}

#Preview("Activity statistics") { ActivityStatisticsView(model: PreviewHelper.model()) }
#Preview("Empty statistics") { ActivityStatisticsView(model: PreviewHelper.model(empty: true)) }
