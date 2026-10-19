import SwiftUI
import SpamWiseCore

/// Shows an operation's latest result: neutral text, or a tinted warning with its recovery action.
struct OperationStatusView: View {
  let operation: TrackedOperation
  var identifier: String?

  var body: some View {
    StatusLabel(status: operation.status, identifier: identifier) {
      operation.retryFailed()
    }
  }
}

/// Neutral text or a tinted warning with a recovery action, for a status that has no operation.
struct StatusLabel: View {
  let status: OperationStatus?
  var identifier: String?
  var retry: () -> Void = {}

  var body: some View {
    switch status {
      case .message(let text):
        Text(text).foregroundStyle(.secondary).textSelection(.enabled)
          .accessibilityIdentifier(identifier ?? "operation.status")
      case .failure(let failure):
        FailureLabel(failure: failure, identifier: identifier, retry: retry)
      case nil: EmptyView()
    }
  }
}

private struct FailureLabel: View {
  private static let automationSettings = URL(
    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
  )
  let failure: OperationFailure
  let identifier: String?
  let retry: () -> Void
  @Environment(\.openURL)
  private var openURL

  var body: some View {
    VStack(alignment: .leading) {
      Label {
        Text(failure.description).textSelection(.enabled)
          .accessibilityIdentifier(identifier ?? "operation.status")
      } icon: {
        Image(systemName: "exclamationmark.triangle.fill").symbolRenderingMode(.multicolor)
          .accessibilityLabel("Warning")
      }
      switch failure.recovery {
        case .openAutomationSettings:
          Button("Open Automation Settings") {
            if let url = Self.automationSettings { openURL(url) }
          }
        case .tryAgain: Button("Try Again", action: retry)
        case nil: EmptyView()
      }
    }
  }
}

#Preview("Message") { StatusLabel(status: .message("Folder plan saved.")).padding() }
#Preview("Permission failure") {
  StatusLabel(status: .failure(OperationFailure(IntegrationError.permissionDenied))).padding()
}
#Preview("Retryable failure") {
  StatusLabel(status: .failure(OperationFailure(IntegrationError.unavailable, retry: .tryAgain)))
    .padding()
}
