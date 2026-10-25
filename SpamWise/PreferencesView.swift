import SwiftUI
import SpamWiseCore

/// The Preferences tab: what the user wants for each kind of graymail, in their own words too.
struct PreferencesView: View {
  private static let editorMinimumHeight: CGFloat = 120
  let preferences: PreferencesModel
  let settings: SettingsModel
  @State private var confirmsReset = false

  var body: some View {
    @Bindable var policy = settings.policy
    Form {
      CategorySuggestionsView(preferences: preferences)
      CategoryPreferencesView(preferences: preferences)
      Section {
        TextEditor(text: $policy.value)
          .font(.body)
          .frame(minHeight: Self.editorMinimumHeight)
          .accessibilityLabel("Additional instructions")
          .accessibilityIdentifier("settings.policy")
          .commitsDraft(policy)
        PolicyLength(policy: policy)
      } header: {
        Text("Additional instructions")
      } footer: {
        Text(
          """
          Anything the choices above don’t cover, in your own words, such as “Newsletters about \
          aviation are fine.” Your instructions are sent to your selected provider with eligible \
          messages.
          """
        )
        .foregroundStyle(.secondary)
      }
      JunkFolderImportView(preferences: preferences)
      Section {
        HStack {
          Button("Reset to defaults") { confirmsReset = true }
          Spacer()
          HelpButton(page: "how-decisions-are-made")
        }
      }
    }
    .formStyle(.grouped)
    .confirmationDialog(
      "Restore the default preferences?",
      isPresented: $confirmsReset,
      titleVisibility: .visible
    ) {
      Button("Restore Defaults", role: .destructive) { settings.resetPreferences() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Your choices are restored and your additional instructions are cleared.")
    }
  }
}

/// Category changes that the user's own corrections keep asking for, applied only on request.
private struct CategorySuggestionsView: View {
  let preferences: PreferencesModel

  var body: some View {
    let suggestions = preferences.categorySuggestions
    if !suggestions.isEmpty {
      Section {
        ForEach(suggestions) { suggestion in
          LabeledContent {
            Button(suggestion.preference.localizedDescription) {
              preferences.setPreference(suggestion.preference, for: suggestion.category)
            }
            .accessibilityIdentifier("preferences.suggestion.\(suggestion.category.rawValue)")
          } label: {
            Text(suggestion.category.localizedName)
            Text("Your corrections for \(suggestion.domainCount) senders agree.")
          }
        }
      } header: {
        Text("Suggested from your corrections")
      }
    }
  }
}

/// The instructions' length against its limit, or why an edit isn't saved.
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
                "Not saved. Shorten your instructions to \(ClassificationLimits.maximumPolicyCharacters) characters or fewer."
            )
          )
        ),
        identifier: "settings.policyTooLong"
      )
    }
  }
}

#Preview("Preferences") {
  let model = PreviewHelper.model()
  return PreferencesView(preferences: model.preferences, settings: model.settings)
}
#Preview("Too long") {
  let model = PreviewHelper.model()
  model.settings.policy.value = String(
    repeating: "Unwanted. ",
    count: ClassificationLimits.maximumPolicyCharacters
  )
  return PreferencesView(preferences: model.preferences, settings: model.settings)
}
