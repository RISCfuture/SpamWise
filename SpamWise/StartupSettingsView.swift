import SwiftUI
import ServiceManagement

struct StartupSettingsView: View {
  @State private var status = SMAppService.mainApp.status
  @State private var failure = ""
  @State private var busy = false
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    Section("Startup") {
      Toggle(
        "Open SpamWise at login",
        isOn: Binding(
          get: { status == .enabled || status == .requiresApproval },
          set: { setEnabled($0) }
        )
      )
      .disabled(busy)
      .accessibilityIdentifier("settings.login")
      if status == .requiresApproval {
        Button("Approve in Login Items Settings") { SMAppService.openSystemSettingsLoginItems() }
      }
      Text(
        "Filtering continues with windows closed. Keep Mail and SpamWise running on an awake Mac."
      )
      .foregroundStyle(.secondary)
      if !failure.isEmpty { Text(failure).foregroundStyle(.secondary) }
    }
    .onChange(of: scenePhase) { _, _ in status = SMAppService.mainApp.status }
  }

  private func setEnabled(_ enabled: Bool) {
    busy = true
    Task {
      defer { busy = false; status = SMAppService.mainApp.status }
      do {
        if enabled {
          try SMAppService.mainApp.register()
        } else {
          try await SMAppService.mainApp.unregister()
        }
        failure = ""
      } catch {
        failure = String(
          localized: "Login registration failed. Check Login Items in System Settings."
        )
      }
    }
  }
}

#Preview("Startup") { Form { StartupSettingsView() }.formStyle(.grouped) }
