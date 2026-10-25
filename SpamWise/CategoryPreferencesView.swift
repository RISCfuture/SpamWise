import SwiftUI
import SpamWiseCore

/// One row per kind of graymail with the user's choice: keep it, flag it for Review, or junk it.
struct CategoryPreferencesView: View {
  let preferences: PreferencesModel

  var body: some View {
    Section {
      ForEach(MailCategory.graymail, id: \.self) { category in
        CategoryPreferenceRow(
          category: category,
          preference: Binding(
            get: { preferences.preference(for: category) },
            set: { preferences.setPreference($0, for: category) }
          )
        )
      }
    } header: {
      Text("Mail you might not want")
    } footer: {
      Text(
        """
        Personal mail, receipts and account notices always stay in your Inbox, and spam and scams \
        always go to Review or Junk. Junk moves wait until SpamWise is confident enough for your \
        filtering strength; until then the message is flagged.
        """
      )
      .foregroundStyle(.secondary)
    }
  }
}

private struct CategoryPreferenceRow: View {
  let category: MailCategory
  @Binding var preference: GraymailPreference

  var body: some View {
    LabeledContent {
      Picker(category.localizedName, selection: $preference) {
        ForEach(GraymailPreference.allCases, id: \.self) { choice in
          Text(choice.localizedTitle).tag(choice)
            .accessibilityLabel(choice.localizedDescription)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .fixedSize()
      .accessibilityIdentifier("preferences.\(category.rawValue)")
    } label: {
      Text(category.localizedName)
      Text(category.localizedExample)
    }
  }
}

#Preview("Preferences") {
  Form { CategoryPreferencesView(preferences: PreviewHelper.model().preferences) }
    .formStyle(.grouped)
}
