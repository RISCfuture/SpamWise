import SwiftUI

/// A sheet's only button: Done, which Escape also activates.
struct DoneToolbarItem: ToolbarContent {
  let dismiss: DismissAction
  var identifier = "sheet.done"

  var body: some ToolbarContent {
    ToolbarItem(placement: .cancellationAction) {
      Button("Done") { dismiss() }
        .keyboardShortcut(.cancelAction)
        .accessibilityIdentifier(identifier)
    }
  }
}

/// A sheet's Cancel and primary buttons, activated by Escape and Return.
struct ConfirmationToolbarItems: ToolbarContent {
  let confirmTitle: LocalizedStringKey
  var confirmIdentifier = "sheet.confirm"
  var canConfirm = true
  let cancel: () -> Void
  let confirm: () -> Void

  var body: some ToolbarContent {
    ToolbarItem(placement: .cancellationAction) {
      Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
    }
    ToolbarItem(placement: .confirmationAction) {
      Button(confirmTitle, action: confirm)
        .keyboardShortcut(.defaultAction)
        .disabled(!canConfirm)
        .accessibilityIdentifier(confirmIdentifier)
    }
  }
}

/// The status a file export leaves behind.
enum ExportResult {
  /// Nothing after a successful export; `failure` as a warning after a failed one.
  static func status(of result: Result<URL, any Error>, failure: LocalizedStringResource)
    -> OperationStatus?
  {
    guard case .failure = result else { return nil }
    return .failure(OperationFailure(message: String(localized: failure)))
  }
}
