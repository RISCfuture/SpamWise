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

  private var selected: DecisionRecord? {
    model.state.records.first { $0.id == selection }
  }

  var body: some View {
    VStack(spacing: 0) {
      Table(model.state.records.reversed(), selection: $selection) {
        TableColumn("Time") { row in
          Text(row.date, format: .dateTime.hour().minute())
        }.width(min: 60, ideal: 75)
        TableColumn("Sender", value: \.sender).width(min: 120, ideal: 180)
        TableColumn("Subject") { row in
          Text(row.subject).accessibilityIdentifier("activity.subject.\(row.id)")
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
  }
}

private struct ActivityStatusView: View {
  let model: AppModel

  private var mode: LocalizedStringKey {
    if model.state.settings.paused { return "Filtering paused" }
    return model.state.settings.dryRun
      ? "Dry run — mail stays unchanged" : "Filtering validated accounts"
  }

  private var modeValue: String {
    if model.state.settings.paused { return "paused" }
    return model.state.settings.dryRun ? "dryRun" : "active"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Divider()
      HStack {
        Text(mode).accessibilityIdentifier("activity.mode").accessibilityValue(modeValue)
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

#Preview("Activity table") { ActivityView(model: PreviewHelper.model()) }
