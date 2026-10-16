import SwiftUI
import SpamWiseCore

/// An Activity command offered in the toolbar, the Filtering menu and the menu bar.
enum ActivityAction: CaseIterable {
  /// Previews recent Inbox mail without moving anything.
  case dryRun
  /// Opens this week's Review digest.
  case digest
  /// Opens the read-only Junk review.
  case junkReview
  /// Opens Activity statistics.
  case statistics

  var title: String {
    switch self {
      case .dryRun: String(localized: "Dry Run Recent Mail")
      case .digest: String(localized: "Review Digest")
      case .junkReview: String(localized: "Review Junk")
      case .statistics: String(localized: "Statistics")
    }
  }
  var systemImage: String {
    switch self {
      case .dryRun: "eye"
      case .digest: "tray.full"
      case .junkReview: "xmark.bin"
      case .statistics: "chart.bar"
    }
  }
  var help: String {
    switch self {
      case .dryRun:
        String(localized: "See how SpamWise would sort your newest mail. Nothing moves.")
      case .digest: String(localized: "Go through this week’s mail marked for Review.")
      case .junkReview: String(localized: "Look through Junk and restore anything that isn’t junk.")
      case .statistics:
        String(localized: "See how many messages SpamWise sorted, by day and account.")
    }
  }
  /// The sheet the action presents, if it presents one.
  var sheet: ActivitySheet? {
    switch self {
      case .dryRun: nil
      case .digest: .digest
      case .junkReview: .junkReview
      case .statistics: .statistics
    }
  }
}

/// A button for an ``ActivityAction``, with its symbol and tooltip.
struct ActivityActionButton: View {
  let action: ActivityAction
  let perform: () -> Void

  var body: some View {
    Button(action: perform) { Label(action.title, systemImage: action.systemImage) }
      .help(action.help)
  }
}

/// Pauses or resumes filtering; its symbol shows what it will do.
struct PauseFilteringButton: View {
  let settings: SettingsModel
  let paused: Bool

  var body: some View {
    Button {
      settings.togglePause()
    } label: {
      if paused {
        Label("Resume Filtering", systemImage: "play.circle")
      } else {
        Label("Pause Filtering", systemImage: "pause.circle")
      }
    }
    .help(
      paused
        ? "Filtering is paused. Resume to sort new mail again."
        : "Stop sorting new mail until you resume. Mail already sorted stays where it is."
    )
  }
}

/// Shows or hides the selected decision's inspector.
struct InspectorToggle: View {
  @Bindable var router: ActivityRouter

  var body: some View {
    Button {
      router.showsInspector.toggle()
    } label: {
      if router.showsInspector {
        Label("Hide Inspector", systemImage: "sidebar.trailing")
      } else {
        Label("Show Inspector", systemImage: "sidebar.trailing")
      }
    }
    .help(router.showsInspector ? "Hide the decision’s details" : "Show the decision’s details")
  }
}

#Preview("Actions") {
  let model = PreviewHelper.model()
  VStack(alignment: .leading) {
    PauseFilteringButton(settings: model.settings, paused: false)
    PauseFilteringButton(settings: model.settings, paused: true)
    ForEach(ActivityAction.allCases, id: \.self) {
      ActivityActionButton(action: $0) {}
    }
    InspectorToggle(router: model.router)
  }.padding()
}
