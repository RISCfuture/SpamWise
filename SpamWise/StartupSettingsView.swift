import SwiftUI
import ServiceManagement

/// Whether SpamWise opens at login, so it keeps checking mail after a restart.
struct StartupSettingsView: View {
  let loginItem: LoginItemModel
  @Environment(\.scenePhase)
  private var scenePhase

  var body: some View {
    Section("Startup") {
      Toggle(
        "Open SpamWise at login",
        isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.setEnabled($0) })
      )
      .disabled(loginItem.operation.isBusy)
      .accessibilityIdentifier("settings.login")
      if loginItem.requiresApproval {
        Text("macOS needs your approval before SpamWise can open at login.")
          .foregroundStyle(.secondary)
        Button("Open Login Items Settings") { SMAppService.openSystemSettingsLoginItems() }
      }
      Text(
        """
        SpamWise checks mail while it’s open, even with its windows closed. At login it opens \
        without a window; use its menu bar item or Dock icon. Mail must be open too.
        """
      )
      .foregroundStyle(.secondary)
      OperationStatusView(operation: loginItem.operation)
    }
    .onAppear { loginItem.refresh() }
    .onChange(of: scenePhase) { _, _ in loginItem.refresh() }
  }
}

#Preview("Startup") {
  Form { StartupSettingsView(loginItem: LoginItemModel()) }.formStyle(.grouped)
}
