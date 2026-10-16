import SwiftUI
import SpamWiseCore

struct SettingsView: View {
  @Bindable var model: AppModel
  @AppStorage private var selectedPane: SettingsPane

  var body: some View {
    VStack(spacing: 0) {
      TabView(selection: $selectedPane) {
        GeneralSettingsView(model: model)
          .tabItem { Label("General", systemImage: "gearshape") }.tag(SettingsPane.general)
        AccountSettingsView(model: model)
          .tabItem { Label("Accounts", systemImage: "person.crop.circle") }.tag(
            SettingsPane.accounts
          )
        RuleEditorView(model: model)
          .tabItem { Label("Rules", systemImage: "line.3.horizontal.decrease") }.tag(
            SettingsPane.rules
          )
        PolicyView(model: model)
          .tabItem { Label("Preferences", systemImage: "text.alignleft") }.tag(
            SettingsPane.preferences
          )
        AdvancedSettingsView(model: model)
          .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }.tag(
            SettingsPane.advanced
          )
      }
      if !model.status.isEmpty {
        Divider()
        Text(model.status).foregroundStyle(.secondary).textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading).padding()
      }
    }
    .navigationTitle(selectedPane.title)
    .frame(minWidth: 640, idealWidth: 700, maxWidth: 800, minHeight: 540, idealHeight: 640)
  }

  init(model: AppModel) {
    self.model = model
    _selectedPane = AppStorage(
      wrappedValue: .general,
      "settings.selectedPane",
      store: model.preferences
    )
  }

  private enum SettingsPane: String {
    case general, accounts, rules, preferences, advanced
    var title: LocalizedStringResource {
      switch self {
        case .general: "General"
        case .accounts: "Accounts"
        case .rules: "Rules"
        case .preferences: "Preferences"
        case .advanced: "Advanced"
      }
    }
  }
}

#Preview("Settings") { SettingsView(model: PreviewHelper.model()) }
