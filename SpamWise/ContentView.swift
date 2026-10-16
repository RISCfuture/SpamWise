import SwiftUI
import SpamWiseCore

struct ContentView: View {
  @Bindable var model: AppModel
  @State private var selection: UUID?
  var selected: DecisionRecord? { model.state.records.first { $0.id == selection } }
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        VStack(alignment: .leading, spacing: 5) {
          Text("Activity").accessibilityIdentifier("activity.title").font(.largeTitle.bold())
          Label(
            model.state.settings.paused
              ? "Filtering paused"
              : model.state.settings.dryRun
                ? "Dry run — mail stays unchanged" : "Filtering validated accounts",
            systemImage: model.state.settings.paused ? "pause.circle" : "shield.checkered"
          )
          .foregroundStyle(.secondary).accessibilityIdentifier("activity.mode")
        }
        Spacer()
        if model.busy { ProgressView().controlSize(.small); Button("Cancel") { model.cancel() } }
        Button(model.state.settings.paused ? "Resume filtering" : "Pause filtering") {
          model.togglePause()
        }.accessibilityIdentifier("activity.pause")
        Button("Dry run recent mail") { model.scan() }.disabled(model.busy || !model.storageReady)
        Button("Review digest") { model.showDigest = true }
        SettingsLink { Image(systemName: "gearshape") }.accessibilityLabel("Open Settings")
          .accessibilityIdentifier("activity.settings")
        HelpButton(page: "how-decisions-are-made")
      }.padding(22)
      Divider()
      HSplitView {
        Table(model.state.records.reversed(), selection: $selection) {
          TableColumn("Time") { row in Text(row.date, format: .dateTime.hour().minute()) }.width(60)
          TableColumn("Sender", value: \.sender).width(min: 100, ideal: 160)
          TableColumn("Subject") { row in
            Text(row.subject).accessibilityIdentifier("activity.subject.\(row.id)")
          }.width(min: 130, ideal: 230)
          TableColumn("Verdict") { row in VerdictBadge(record: row) }.width(100)
          TableColumn("Confidence") { row in Text(row.verdict.map { "\($0.confidence)%" } ?? "—") }
            .width(80)
          TableColumn("Reason") { row in Text(row.decision.reason).lineLimit(2) }.width(
            min: 130,
            ideal: 220
          )
        }.overlay {
          if model.state.records.isEmpty {
            ContentUnavailableView(
              "No decisions yet",
              systemImage: "tray",
              description: model.state.settings.onboardingComplete
                ? Text("Try a dry run on recent mail.")
                : Text("Finish setup, then try a dry run on recent mail.")
            )
          }
        }
        if let selected {
          DecisionDetailView(model: model, row: selected).frame(
            minWidth: 270,
            idealWidth: 300,
            maxWidth: 380
          )
        }
      }
      Divider()
      HStack {
        Text(
          "Decisions today: \(model.today.count) · Junk: \(model.today.filter { $0.decision.label == .junk }.count) · Review: \(model.today.filter { $0.decision.label == .review }.count)"
        )
        Spacer()
        Text("Month API cost ≈ \(model.monthCost, format: .currency(code: "USD"))").help(
          "Estimated cost from measured or explicitly estimated token counts; cache-write premiums may differ."
        )
      }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.top, 10)
      HStack {
        Text(model.status).font(.caption).textSelection(.enabled).accessibilityIdentifier(
          "activity.status"
        )
        Spacer()
      }.padding(.horizontal, 20).padding(.bottom, 12).padding(.top, 6)
    }
    .frame(minWidth: 900, minHeight: 560)
    .sheet(isPresented: $model.showDigest) { ReviewDigestView(model: model) }
    .sheet(
      isPresented: Binding(
        get: { !model.state.settings.onboardingComplete || model.showSetup },
        set: { model.showSetup = $0 }
      )
    ) {
      OnboardingView(model: model).interactiveDismissDisabled(
        !model.state.settings.onboardingComplete
      )
    }
  }
}

struct DecisionDetailView: View {
  var model: AppModel
  var row: DecisionRecord
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        Text(row.subject).font(.title3.bold())
        Text(row.sender).foregroundStyle(.secondary).textSelection(.enabled)
        VerdictBadge(record: row)
        Text(row.decision.reason).textSelection(.enabled)
        LabeledContent("Path", value: row.path)
        LabeledContent("Intended action", value: row.decision.action.localizedTitle)
        LabeledContent("Outcome", value: row.outcome.localizedTitle)
        if let error = row.actionError {
          Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
        }
        if let correction = row.correctedLabel {
          Text("User corrected to \(correction.localizedTitle)").accessibilityIdentifier(
            "correction.label"
          )
        }
        if let usage = row.verdict?.usage {
          Text(
            "\(usage.input) input · \(usage.output) output · \(usage.cached) cached tokens (\(usage.estimated ? "estimated" : "measured"))"
          ).font(.caption)
          Text("Estimated cost: \(usage.estimatedCost, format: .currency(code: "USD"))").font(
            .caption
          )
        }
        Text("Latency: \(row.latency, specifier: "%.2f") s").font(.caption)
        HStack {
          Button("Mark as Good") { model.correct(row, label: .inbox) }
            .accessibilityIdentifier("correction.good")
          Button("Mark as Junk") { model.correct(row, label: .junk) }
            .accessibilityIdentifier("correction.junk")
        }.disabled(model.busy || row.path == "verification")
        Button("Mark as Review") { model.correct(row, label: .review) }
          .accessibilityIdentifier("correction.review").disabled(
            model.busy || row.path == "verification"
          )
        Menu("Correct entire domain…") {
          Button("Allow this domain") { model.correct(row, label: .inbox, scope: .domain) }
            .accessibilityIdentifier("correction.domain.allow")
          Button("Block this domain") { model.correct(row, label: .junk, scope: .domain) }
        }.accessibilityIdentifier("correction.domain")
          .disabled(model.busy || row.evidence?.fromDomain == nil)
        Text(
          """
          Good and Junk corrections create address rules. Review removes the address rule. \
          Explicit domain rules still apply to that domain.
          """
        ).font(.caption).foregroundStyle(.secondary)
        HelpButton(page: "correcting-mistakes")
        if let evidence = row.evidence, let data = try? JSONEncoder.pretty.encode(evidence),
          let text = String(data: data, encoding: .utf8)
        {
          Divider(); Text("Evidence").font(.headline)
          Text(text).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
        }
      }.padding(18)
    }
  }
}
struct VerdictBadge: View {
  var record: DecisionRecord
  var body: some View {
    let label = record.decision.label
    Label(
      label?.localizedTitle ?? String(localized: "Unclassified"),
      systemImage: label == .junk
        ? "tray.full"
        : label == .review ? "flag" : label == .inbox ? "checkmark.circle" : "questionmark.circle"
    )
    .foregroundStyle(label == .junk ? Color.red : label == .review ? Color.orange : Color.primary)
    .accessibilityLabel("Verdict: \(label?.localizedTitle ?? String(localized: "Unclassified"))")
  }
}
extension JSONEncoder {
  static var pretty: JSONEncoder {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
  }
}
