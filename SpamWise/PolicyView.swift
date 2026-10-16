import SwiftUI
import SpamWiseCore

struct PolicyView: View {
  private static let characterLimit = 4000
  @Bindable var model: AppModel
  @State private var policy = ""

  private var localizedDefaultPolicy: String {
    String(
      localized:
        """
        Marketing from retailers I haven’t ordered from is unwanted. Cart and checkout reminders \
        from stores with no order history are unwanted. Shipping notices are wanted only if they \
        match an order in my history. Anything from people I’ve corresponded with is wanted.
        """
    )
  }

  var body: some View {
    VStack(alignment: .leading) {
      Text("Your mail preferences").font(.headline)
      Text(
        "Describe what you want to receive. Your policy is sent to your selected provider with eligible messages."
      )
      .foregroundStyle(.secondary)
      TextEditor(text: $policy)
        .font(.body).border(.separator).accessibilityLabel("Mail filtering policy")
        .accessibilityIdentifier("settings.policy")
      HStack {
        Text("\(policy.count, format: .number)/\(Self.characterLimit, format: .number) characters")
          .foregroundStyle(.secondary)
        Spacer()
        HelpButton(page: "how-decisions-are-made")
      }
      HStack {
        Button("Reset to default") { policy = localizedDefaultPolicy }
        Spacer()
        Button("Save preferences") { model.setSetting(\.policy, to: policy) }
          .disabled(policy.count > Self.characterLimit || model.busy)
          .keyboardShortcut("s", modifiers: .command)
      }
    }.padding()
      .onAppear {
        policy =
          model.state.settings.policy == PromptBuilder.defaultPolicy
          ? localizedDefaultPolicy : model.state.settings.policy
      }
  }
}

#Preview("Preferences") { PolicyView(model: PreviewHelper.model()) }
