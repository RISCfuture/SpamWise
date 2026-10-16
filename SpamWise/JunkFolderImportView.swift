import SwiftUI
import SpamWiseCore

/// Learns from the user's existing Junk folders: scan them, review the senders, save examples.
struct JunkFolderImportView: View {
  let preferences: PreferencesModel

  var body: some View {
    Section {
      if preferences.canScanJunk {
        Text(
          """
          Your Junk folders already show what you don’t want. SpamWise can read up to \
          \(PreferencesModel.maximumScannedPerAccount) recent Junk messages per account and save \
          one example from each sender. It creates no rules and moves no mail.
          """
        )
        HStack {
          Button("Scan Junk Folders", action: preferences.scanJunk)
            .disabled(preferences.scan.isBusy || preferences.importing.isBusy)
            .accessibilityIdentifier("preferences.scanJunk")
          if preferences.scan.isBusy { ProgressView().controlSize(.small) }
        }
        OperationStatusView(operation: preferences.scan)
        if !preferences.junkSenders.isEmpty { JunkSendersSummary(preferences: preferences) }
      } else {
        Text("Learning from Junk folders is available with Apple Mail.")
          .foregroundStyle(.secondary)
      }
    } header: {
      Text("Learn from your Junk folders")
    }
  }
}

private struct JunkSendersSummary: View {
  @Bindable var preferences: PreferencesModel

  var body: some View {
    Text(
      "Found \(preferences.scannedCount) messages from \(preferences.junkSenders.count) senders."
    )
    .accessibilityIdentifier("preferences.junkSummary")
    DisclosureGroup("Choose senders") {
      ForEach(preferences.junkSenders) { sender in
        Toggle(isOn: included(sender)) {
          Text(sender.name)
          if sender.possiblyWanted {
            Text("Possibly wanted: in your Contacts or mail history")
          } else {
            Text("\(sender.messageCount) messages")
          }
        }
      }
    }
    HStack {
      Button("Save \(preferences.includedSenders.count) Examples") {
        preferences.importJunkExamples()
      }
      .disabled(
        preferences.includedSenders.isEmpty || preferences.importing.isBusy
          || preferences.hasImported
      )
      .accessibilityIdentifier("preferences.importJunk")
      if preferences.importing.isBusy { ProgressView().controlSize(.small) }
    }
    OperationStatusView(operation: preferences.importing, identifier: "preferences.importStatus")
  }

  private func included(_ sender: JunkFolderSender) -> Binding<Bool> {
    Binding(
      get: { !preferences.excludedSenders.contains(sender.id) },
      set: { isIncluded in
        if isIncluded {
          preferences.excludedSenders.remove(sender.id)
        } else {
          preferences.excludedSenders.insert(sender.id)
        }
      }
    )
  }
}

#Preview("Learn from Junk") {
  Form { JunkFolderImportView(preferences: PreviewHelper.model().preferences) }
    .formStyle(.grouped)
}
