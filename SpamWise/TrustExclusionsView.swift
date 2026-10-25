import SwiftUI
import SpamWiseCore

/**
 Your own addresses, and addresses that never count as people you know.

 Edits save when editing ends. One that can't be saved stays, with the reason, until it is fixed.
 */
struct TrustExclusionsView: View {
  @Bindable var relationships: RelationshipsModel
  let shared: SharedStateModel
  let imap: IMAPConnectionModel

  /// How SpamWise finds the user's own addresses with the selected connection.
  private var discoveryNote: LocalizedStringKey {
    if shared.settings.advancedOptions.transport == .appleMail {
      "Check Mail Connection to find your account addresses."
    } else if imap.usernameIsNotAddress {
      """
      Your IMAP username isn’t an email address, so SpamWise can’t tell which address is yours. \
      Enter your address below so its mail doesn’t count as from people you know.
      """
    } else {
      "Check Connection above to find your account address."
    }
  }

  var body: some View {
    Section {
      if shared.state.ownAddresses.isEmpty {
        Text(discoveryNote).foregroundStyle(.secondary)
      } else {
        LabeledContent("Your addresses") {
          Text(shared.state.ownAddresses.sorted().joined(separator: "\n"))
            .textSelection(.enabled)
        }
      }
      TextEditor(text: $relationships.exclusionsText).frame(minHeight: 80)
        .accessibilityLabel("Addresses that don’t count as people you know")
        .accessibilityIdentifier("relationships.exclusions")
        .commitsEdits { relationships.commitTrustExclusions() }
      OperationStatusView(operation: relationships.exclusions)
    } header: {
      Text("Your addresses and exceptions")
    } footer: {
      Text(
        """
        Mail from these addresses never counts as from people you know. It isn’t blocked, and your \
        sender rules still apply. Enter one address per line.
        """
      )
      .foregroundStyle(.secondary)
    }
  }
}

#Preview("Trust exclusions") {
  let model = PreviewHelper.model()
  Form {
    TrustExclusionsView(relationships: model.relationships, shared: model.shared, imap: model.imap)
  }
  .formStyle(.grouped)
}
#Preview("Discovered addresses") {
  let model = PreviewHelper.model()
  model.shared.state.ownAddresses = ["me@example.org", "me@icloud.example"]
  return Form {
    TrustExclusionsView(relationships: model.relationships, shared: model.shared, imap: model.imap)
  }
  .formStyle(.grouped)
}
