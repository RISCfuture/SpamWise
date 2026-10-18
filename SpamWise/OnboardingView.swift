import SwiftUI
import SpamWiseCore

struct OnboardingView: View {
  let model: AppModel
  /// Closes setup when it is presented over Settings; nil in the main window.
  var close: (() -> Void)?
  @State private var step: SetupStep = .welcome

  private var isBusy: Bool {
    model.credentials.claudeKey.isBusy || model.mail.check.isBusy || model.imap.operation.isBusy
      || model.scanning.preview.isBusy
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text("Welcome to SpamWise").font(.title2.bold())
        Spacer()
        Text(
          "Step \(step.rawValue + 1, format: .number) of \(SetupStep.allCases.count, format: .number)"
        ).foregroundStyle(.secondary)
      }.padding()
      StatusLabel(status: model.shared.storageStatus)
        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal)
      Form {
        switch step {
          case .welcome:
            SetupIntroductionView(correctionLimit: model.shared.settings.correctionLimit)
          case .account:
            Section("Connect your Anthropic account") {
              KeyEntryView(credentials: model.credentials)
              ProviderConsentView(settings: model.settings, backend: .claude)
            }
          case .mail:
            if model.shared.settings.advancedOptions.transport == .imap {
              IMAPSettingsView(
                settings: model.settings,
                imap: model.imap,
                storageReady: model.services.storageReady
              )
            } else {
              MailConnectionView(model: model)
            }
          case .preview: SetupPreviewView(scanning: model.scanning)
        }
      }.formStyle(.grouped)
      Divider()
      HStack {
        if let close {
          Button("Close", action: close).keyboardShortcut(.cancelAction)
        }
        if let previous = step.previous {
          Button("Back") { step = previous }
        }
        Spacer()
        if isBusy { ProgressView().controlSize(.small) }
        if let next = step.next {
          Button(step == .account ? "Continue offline" : "Continue") { step = next }
            .accessibilityIdentifier("setup.continue").keyboardShortcut(.defaultAction)
        } else {
          Button("Finish setup") {
            model.finishSetup(); close?()
          }
          .accessibilityIdentifier("setup.finish").keyboardShortcut(.defaultAction)
          .disabled(!model.services.storageReady)
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
  let scanning: ScanCoordinator

  var body: some View {
    Section("Try a dry run") {
      Text(
        """
        Preview up to 20 recent Inbox messages without changing them. Eligible messages use your \
        selected provider and may incur API charges.
        """
      )
      HStack {
        Button("Dry run 20 recent messages") { scanning.previewRecent(limit: 20) }
        if scanning.preview.isBusy {
          ProgressView().controlSize(.small)
          Button("Stop Dry Run") { scanning.preview.cancel() }
        }
      }
      OperationStatusView(operation: scanning.preview)
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
#Preview("Dry run") {
  Form { SetupPreviewView(scanning: PreviewHelper.model().scanning) }.formStyle(.grouped)
}
