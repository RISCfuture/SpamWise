import SwiftUI
import ServiceManagement

/// Whether SpamWise opens at login, so it keeps checking mail after a restart.
struct StartupSettingsView: View {
  @State private var status = SMAppService.mainApp.status
  @State private var failure: OperationStatus?
  @State private var busy = false
  @Environment(\.scenePhase)
  private var scenePhase

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
        Text("macOS needs your approval before SpamWise can open at login.")
          .foregroundStyle(.secondary)
        Button("Open Login Items Settings") { SMAppService.openSystemSettingsLoginItems() }
      }
      Text(
        "SpamWise checks mail while it’s open, even with its windows closed. Mail must be open too."
      )
      .foregroundStyle(.secondary)
      StatusLabel(status: failure)
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
        failure = nil
      } catch {
        failure = .failure(
          OperationFailure(
            message: String(
              localized:
                "SpamWise couldn’t change its login item. Check Login Items in System Settings › General."
            )
          )
        )
      }
    }
  }
}

#Preview("Startup") { Form { StartupSettingsView() }.formStyle(.grouped) }
