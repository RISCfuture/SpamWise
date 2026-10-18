import SwiftUI
import SpamWiseCore

struct OnboardingView: View {
  @Bindable var model: AppModel
  var completion: () -> Void = {}
  @State private var step: SetupStep = .welcome

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text("Welcome to SpamWise").font(.title2.bold())
        Spacer()
        Text(
          "Step \(step.rawValue + 1, format: .number) of \(SetupStep.allCases.count, format: .number)"
        ).foregroundStyle(.secondary)
      }.padding()
      Form {
        switch step {
          case .welcome:
            SetupIntroductionView(correctionLimit: model.state.settings.correctionLimit)
          case .account:
            Section("Connect your Anthropic account") {
              KeyEntryView(model: model)
              ProviderConsentView(model: model, backend: .claude)
            }
          case .mail:
            if model.state.settings.advancedOptions.transport == .imap {
              IMAPSettingsView(model: model)
            } else {
              MailConnectionView(model: model)
            }
          case .preview: SetupPreviewView(model: model)
        }
      }.formStyle(.grouped)
      Divider()
      HStack {
        if let previous = step.previous {
          Button("Back") { step = previous }.disabled(model.busy)
        }
        Spacer()
        if model.busy { ProgressView().controlSize(.small) }
        if let next = step.next {
          Button(step == .account ? "Continue offline" : "Continue") { step = next }
            .accessibilityIdentifier("setup.continue").keyboardShortcut(.defaultAction)
            .disabled(model.busy)
        } else {
          Button("Finish setup") {
            model.finishSetup(); completion()
          }
          .accessibilityIdentifier("setup.finish").keyboardShortcut(.defaultAction)
          .disabled(!model.storageReady || model.busy)
        }
      }.padding()
    }
    .frame(minWidth: 560, idealWidth: 640, maxWidth: 760, minHeight: 480, idealHeight: 560)
  }

  private enum SetupStep: Int, CaseIterable {
    case welcome, account, mail, preview
    var previous: Self? { Self(rawValue: rawValue - 1) }
    var next: Self? { Self(rawValue: rawValue + 1) }
  }
}

private struct SetupIntroductionView: View {
  let correctionLimit: Int

  var body: some View {
    Section {
      Text("Your Inbox, with fewer distractions").font(.headline)
        .accessibilityIdentifier("setup.intro")
      Text(
        "Preview decisions before changing your mail. Uncertain messages stay in Inbox; SpamWise never deletes mail."
      )
    }
    Section("Your privacy") {
      Text(
        """
        When local rules cannot decide, your selected provider receives a shortened message, your \
        preferences, and up to \(correctionLimit, format: .number) similar corrections from the \
        same account, each with its sender domain, subject, a short excerpt and your label.
        """
      )
      Text(
        """
        Automatic filtering covers only mail received after setup. Older mail is sent to your \
        provider only when you preview it.
        """
      )
      Text("Optional domain-age lookups share the sender’s domain with registration services.")
      HStack {
        Text("API keys stay in Keychain. You can complete setup offline.")
        Spacer()
        HelpButton(page: "what-data-is-sent")
      }
    }
  }
}

private struct SetupPreviewView: View {
  let model: AppModel

  var body: some View {
    Section("Try a dry run") {
      Text(
        """
        Preview up to 20 recent Inbox messages without changing them. Eligible messages use your \
        selected provider and may incur API charges.
        """
      )
      Button("Dry run 20 recent messages") { model.scan(limit: 20) }.disabled(model.busy)
      Text(model.status).textSelection(.enabled)
    }
    Section {
      Text("You can finish setup offline and return to Settings later.").foregroundStyle(.secondary)
    }
  }
}

#Preview("Onboarding") { OnboardingView(model: PreviewHelper.model(onboarding: true)) }
#Preview("Introduction") {
  Form { SetupIntroductionView(correctionLimit: 5) }.formStyle(.grouped)
}
#Preview("Dry run") { Form { SetupPreviewView(model: PreviewHelper.model()) }.formStyle(.grouped) }
