import SwiftUI
import SpamWiseCore

struct SettingsView: View {
  let model: AppModel
  @AppStorage private var selectedPane: SettingsPane
  @State private var showsSetup = false

  private var saveFailure: Binding<Bool> {
    Binding(
      get: { model.settings.saveFailure != nil },
      set: { if !$0 { model.settings.saveFailure = nil } }
    )
  }

  var body: some View {
    Group {
      if model.shared.hasLoadedSettings {
        TabView(selection: $selectedPane) {
          ForEach(SettingsPane.allCases) { pane in
            Tab(value: pane) {
              SettingsPaneView(pane: pane, model: model) { showsSetup = true }
            } label: {
              Label {
                Text(pane.title)
              } icon: {
                Image(systemName: pane.systemImage)
              }
            }
          }
        }
        .navigationTitle(Text(selectedPane.title))
      } else {
        StorageLoadingView(
          shared: model.shared,
          unavailableTitle: "Settings Unavailable",
          loadingTitle: "Loading settings…"
        )
      }
    }
    .frame(minWidth: 640, idealWidth: 700, maxWidth: 800, minHeight: 540, idealHeight: 640)
    .sheet(isPresented: $showsSetup) {
      OnboardingView(model: model) { showsSetup = false }
    }
    .alert(
      "Settings couldn’t be saved",
      isPresented: saveFailure,
      presenting: model.settings.saveFailure
    ) { _ in
      Button("OK") {}
    } message: { failure in
      Text(failure.description)
    }
  }

  init(model: AppModel) {
    self.model = model
    _selectedPane = AppStorage(
      wrappedValue: .general,
      "settings.selectedPane",
      store: model.services.preferences
    )
  }
}

/// A tab of the Settings window.
enum SettingsPane: String, CaseIterable, Identifiable {
  case general, classifier, accounts, rules, preferences, advanced

  var id: Self { self }
  var title: LocalizedStringResource {
    switch self {
      case .general: "General"
      case .classifier: "Provider"
      case .accounts: "Accounts"
      case .rules: "Rules"
      case .preferences: "Mail Choices"
      case .advanced: "Advanced"
    }
  }
  var systemImage: String {
    switch self {
      case .general: "gearshape"
      case .classifier: "sparkles"
      case .accounts: "at"
      case .rules: "line.3.horizontal.decrease"
      case .preferences: "slider.horizontal.3"
      case .advanced: "gearshape.2"
    }
  }
}

/// The content of one Settings tab, given the models it needs.
private struct SettingsPaneView: View {
  let pane: SettingsPane
  let model: AppModel
  let showSetup: () -> Void

  var body: some View {
    switch pane {
      case .general:
        GeneralSettingsView(model: model, showSetup: showSetup)
      case .classifier:
        ClassifierSettingsView(model: model)
      case .accounts:
        AccountSettingsView(model: model)
      case .rules:
        RuleEditorView(rules: model.rules, shared: model.shared)
      case .preferences:
        PreferencesView(preferences: model.preferences, settings: model.settings)
      case .advanced:
        AdvancedSettingsView(model: model)
    }
  }
}

#Preview("Settings") { SettingsView(model: PreviewHelper.model()) }
