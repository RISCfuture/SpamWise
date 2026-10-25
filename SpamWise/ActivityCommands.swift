import SwiftUI
import SpamWiseCore

extension FocusedValues {
  /// The decision selected in the Activity window.
  @Entry var selectedDecision: DecisionRecord?
}

/// The Filtering, View and Tools menu commands that mirror the Activity toolbar and inspector.
struct ActivityCommands: Commands {
  let model: AppModel

  var body: some Commands {
    CommandMenu("Filtering") {
      FilteringMenuItems(model: model)
    }
    CommandGroup(after: .toolbar) {
      ViewMenuItems(model: model)
    }
    CommandMenu("Tools") {
      ToolsMenuItems(model: model)
    }
  }
}

/// Opens the Activity window and presents `sheet` in it.
@MainActor
private func show(
  _ sheet: ActivitySheet,
  router: ActivityRouter,
  openWindow: OpenWindowAction
) {
  openWindow(id: "activity")
  router.present(sheet)
}

private struct FilteringMenuItems: View {
  let model: AppModel
  @FocusedValue(\.selectedDecision)
  private var selected
  @Environment(\.openWindow)
  private var openWindow

  var body: some View {
    PauseFilteringButton(settings: model.settings, paused: model.shared.settings.paused)
      .disabled(!model.canCorrectMail)
    ActivityActionButton(action: .dryRun) {
      openWindow(id: "activity")
      model.scanning.previewRecent()
    }
    .disabled(!model.canCorrectMail)
    ForEach([ActivityAction.digest, .junkReview], id: \.self) { action in
      ActivityActionButton(action: action) {
        if let sheet = action.sheet { show(sheet, router: model.router, openWindow: openWindow) }
      }
      .disabled(!model.shared.settings.onboardingComplete)
    }
    Divider()
    SelectedDecisionCorrections(
      corrections: model.corrections,
      router: model.router,
      selected: selected
    )
    if let selected, selected.isRetryable {
      Button("Classify Again") {
        model.router.showsInspector = true
        model.corrections.retryClassification(selected)
      }
      .disabled(!model.corrections.canRetry(selected))
    }
  }
}

/// A verdict correction Activity offers for one decision, with its key equivalent.
struct DecisionCorrectionCommand {
  /// Good, Junk and Review, in menu order.
  static let all = [
    Self(label: .inbox, key: "g"), Self(label: .junk, key: "j"), Self(label: .review, key: "r")
  ]
  /// The modifiers of every correction’s key equivalent.
  static let modifiers: EventModifiers = [.command, .option]
  /// The verdict the correction records.
  let label: MailLabel
  /// The key that, with ``modifiers``, chooses the correction.
  let key: KeyEquivalent
  /// The menu item’s identifier, `activity.correct.<label>`.
  var identifier: String { "activity.correct.\(label.rawValue)" }
}

/**
 Corrects the decision selected in Activity, with Mail-like shortcuts.

 Each correction shows the inspector, where its status and any confirmation it needs appear.
 */
private struct SelectedDecisionCorrections: View {
  let corrections: CorrectionsModel
  let router: ActivityRouter
  let selected: DecisionRecord?

  var body: some View {
    ForEach(DecisionCorrectionCommand.all, id: \.label) { command in
      Button(command.label.correctionTitle) {
        guard let selected else { return }
        router.showsInspector = true
        corrections.correct(selected, label: command.label)
      }
      .keyboardShortcut(command.key, modifiers: DecisionCorrectionCommand.modifiers)
      .disabled(selected.map { !corrections.canCorrect($0) } ?? true)
      .accessibilityIdentifier(command.identifier)
    }
  }
}

private struct ViewMenuItems: View {
  let model: AppModel
  @Environment(\.openWindow)
  private var openWindow

  var body: some View {
    InspectorToggle(router: model.router)
      .keyboardShortcut("i", modifiers: [.command, .option])
    ActivityActionButton(action: .statistics) {
      show(.statistics, router: model.router, openWindow: openWindow)
    }
    .disabled(!model.shared.settings.onboardingComplete)
  }
}

private struct ToolsMenuItems: View {
  let model: AppModel
  @Environment(\.openWindow)
  private var openWindow

  var body: some View {
    Button("Reviewed Messages…") { show(.corpus, router: model.router, openWindow: openWindow) }
      .accessibilityIdentifier("activity.corpus")
      .disabled(!model.shared.settings.onboardingComplete)
    Button("Configuration History") {
      show(.audit, router: model.router, openWindow: openWindow)
    }
    .disabled(!model.shared.settings.onboardingComplete)
  }
}
