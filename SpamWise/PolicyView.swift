import SwiftUI
import SpamWiseCore

/// The Policy tab: what the user wants to receive, in their own words, saved as they type.
struct PolicyView: View {
  private static let editorMinimumHeight: CGFloat = 220
  let settings: SettingsModel
  @State private var confirmsReset = false

  var body: some View {
    @Bindable var policy = settings.policy
    Form {
      Section {
        TextEditor(text: $policy.value)
          .font(.body)
          .frame(minHeight: Self.editorMinimumHeight)
          .accessibilityLabel("Mail filtering policy")
          .accessibilityIdentifier("settings.policy")
          .commitsDraft(policy)
        PolicyLength(policy: policy)
      } header: {
        Text("Your mail policy")
      } footer: {
        Text(
          "Describe what you want to receive. Your policy is sent to your selected provider with eligible messages."
        )
        .foregroundStyle(.secondary)
      }
      Section {
        HStack {
          Button("Reset to default") { confirmsReset = true }
            .disabled(policy.value == SettingsModel.localizedDefaultPolicy)
          Spacer()
          HelpButton(page: "how-decisions-are-made")
        }
      }
    }
    .formStyle(.grouped)
    .confirmationDialog(
      "Replace your policy with the default?",
      isPresented: $confirmsReset,
      titleVisibility: .visible
    ) {
      Button("Replace Policy", role: .destructive) { settings.resetPolicy() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Your current policy text will be replaced.")
    }
  }
}

/// The policy's length against its limit, or why an edit isn't saved.
private struct PolicyLength: View {
  let policy: SettingDraft<String>

  var body: some View {
    if policy.isAcceptable {
      Text(
        "\(policy.value.count) of \(ClassificationLimits.maximumPolicyCharacters) characters"
      )
      .foregroundStyle(.secondary)
      .monospacedDigit()
    } else {
      StatusLabel(
        status: .failure(
          OperationFailure(
            message: String(
              localized:
                "Not saved. Shorten your policy to \(ClassificationLimits.maximumPolicyCharacters) characters or fewer."
            )
          )
        ),
        identifier: "settings.policyTooLong"
      )
    }
  }
}

#Preview("Policy") { PolicyView(settings: PreviewHelper.model().settings) }
#Preview("Too long") {
  let settings = PreviewHelper.model().settings
  settings.policy.value = String(
    repeating: "Unwanted. ",
    count: ClassificationLimits.maximumPolicyCharacters
  )
  return PolicyView(settings: settings)
}
