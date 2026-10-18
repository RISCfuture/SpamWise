import SwiftUI
import FoundationModels
import SpamWiseCore

/**
 The four setup steps: introduction, provider, mail connection and a dry run.

 In the main window it runs once, before Activity. Reopened from Settings as a sheet, it adds
 Cancel, and its last step only dismisses once setup was completed before.
 */
struct OnboardingView: View {
  let model: AppModel
  /// Dismisses setup when it is presented as a sheet; nil in the main window.
  var close: (() -> Void)?
  @State private var step: SetupStep = .welcome
  @State private var draftKey = ""
  @Environment(\.openWindow) private var openWindow

  private var settings: SpamWiseCore.Settings { model.shared.settings }
  private var readiness: ClassifierReadiness {
    ClassifierReadiness(
      settings: settings,
      onDeviceAvailable: SystemLanguageModel.default.isAvailable,
      savedKeys: model.credentials.savedKeys
    )
  }
  private var isBusy: Bool {
    model.credentials.claudeKey.isBusy || model.credentials.providerKey.isBusy
      || model.mail.check.isBusy || model.imap.operation.isBusy || model.scanning.preview.isBusy
  }
  private var showActivity: (() -> Void)? {
    guard let close, settings.onboardingComplete else { return nil }
    return {
      openWindow(id: "activity")
      close()
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      SetupHeader(step: step, isReopened: close != nil)
      StatusLabel(status: model.shared.storageStatus)
        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal)
      Form {
        switch step {
          case .welcome:
            SetupIntroductionView(correctionLimit: settings.correctionLimit)
          case .classifier:
            SetupClassifierView(
              settings: model.settings,
              credentials: model.credentials,
              readiness: readiness,
              draftKey: $draftKey
            )
          case .mail:
            if settings.advancedOptions.transport == .imap {
              IMAPSettingsView(
                settings: model.settings,
                imap: model.imap,
                storageReady: model.services.storageReady
              )
            } else {
              MailConnectionView(model: model)
              RelationshipSettingsView(
                relationships: model.relationships,
                settings: model.settings,
                shared: model.shared
              )
            }
          case .preview:
            SetupPreviewView(
              scanning: model.scanning,
              readiness: readiness,
              backend: settings.advancedOptions.backend,
              onboardingComplete: settings.onboardingComplete,
              showActivity: showActivity
            )
        }
      }.formStyle(.grouped)
      Divider()
      SetupNavigation(
        step: $step,
        isBusy: isBusy,
        canFinish: model.services.storageReady,
        continueTitle: continueTitle,
        continuesByDefault: step != .classifier || draftKey.isEmpty,
        finish: finishTitle,
        cancel: close,
        complete: complete
      )
    }
    .frame(minWidth: 560, idealWidth: 640, maxWidth: 760, minHeight: 480, idealHeight: 560)
    .task { await model.credentials.refreshSavedKeys() }
  }

  private var continueTitle: LocalizedStringKey {
    step == .classifier && !readiness.isReady ? "Skip for now" : "Continue"
  }
  private var finishTitle: LocalizedStringKey {
    close != nil && settings.onboardingComplete ? "Done" : "Finish setup"
  }

  /// Completes first-run setup, or only dismisses when setup was completed before.
  private func complete() {
    if !settings.onboardingComplete { model.finishSetup() }
    close?()
  }
}

/// A setup step, in order.
private enum SetupStep: Int, CaseIterable {
  case welcome, classifier, mail, preview

  var previous: Self? { Self(rawValue: rawValue - 1) }
  var next: Self? { Self(rawValue: rawValue + 1) }
}

private struct SetupHeader: View {
  let step: SetupStep
  let isReopened: Bool

  var body: some View {
    HStack {
      Text(isReopened ? "SpamWise Setup" : "Welcome to SpamWise").font(.title2.bold())
      Spacer()
      Text("Step \(step.rawValue + 1) of \(SetupStep.allCases.count)")
        .foregroundStyle(.secondary)
    }
    .padding()
  }
}

/// Cancel, Back and the step's primary button.
private struct SetupNavigation: View {
  @Binding var step: SetupStep
  let isBusy: Bool
  let canFinish: Bool
  let continueTitle: LocalizedStringKey
  /// Whether Return continues; false while another button on the step should take Return.
  let continuesByDefault: Bool
  let finish: LocalizedStringKey
  /// Dismisses a reopened setup without changing anything; nil in the main window.
  let cancel: (() -> Void)?
  let complete: () -> Void

  var body: some View {
    HStack {
      if let cancel {
        Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
          .accessibilityIdentifier("setup.cancel")
      }
      if let previous = step.previous {
        Button("Back") { step = previous }
      }
      Spacer()
      if isBusy { ProgressView().controlSize(.small) }
      if let next = step.next {
        Button(continueTitle) { step = next }
          .keyboardShortcut(continuesByDefault ? .defaultAction : nil)
          .accessibilityIdentifier("setup.continue")
      } else {
        Button(finish, action: complete)
          .keyboardShortcut(.defaultAction)
          .accessibilityIdentifier("setup.finish")
          .disabled(!canFinish)
      }
    }
    .padding()
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
        Your rules and known senders are checked on this Mac. If you choose a cloud provider, \
        messages they can’t decide are sent to it: a shortened message, your preferences, and up \
        to \(correctionLimit) similar corrections from the same account, each with its sender \
        domain, subject, a short excerpt and your label.
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
        Text("API keys are stored only in Keychain.")
        Spacer()
        HelpButton(page: "what-data-is-sent")
      }
    }
  }
}

#Preview("First run") { OnboardingView(model: PreviewHelper.model(onboarding: true)) }
#Preview("Reopened from Settings") { OnboardingView(model: PreviewHelper.model()) {} }
#Preview("Introduction") {
  Form { SetupIntroductionView(correctionLimit: 5) }.formStyle(.grouped)
}
