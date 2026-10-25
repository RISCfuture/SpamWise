import SwiftUI
import SpamWiseCore
import MailIntegration

/// The Advanced tab: optional evidence, classification context, learning, backups and diagnostics.
struct AdvancedSettingsView: View {
  let model: AppModel

  private var settings: SettingsModel { model.settings }

  var body: some View {
    Form {
      EvidenceSettingsView(settings: settings, credentials: model.credentials)
      ContextSection(settings: settings)
      LearningSettingsView(
        settings: settings,
        shared: model.shared,
        rules: model.rules,
        activity: model.activity
      )
      BackupSettingsView(backup: model.backup)
      DiagnosticsSection(model: model)
    }.formStyle(.grouped)
  }
}

/// How much context accompanies each message; each burst of clicks saves once.
private struct ContextSection: View {
  private static let bodyTokenBudgetStep = 100
  let settings: SettingsModel

  var body: some View {
    @Bindable var corrections = settings.correctionLimit
    @Bindable var bodyBudget = settings.bodyTokenBudget
    Section {
      Stepper(
        "Similar corrections: \(corrections.value)",
        value: $corrections.value,
        in: ClassificationLimits.correctionLimitRange
      )
      Stepper(
        "Message text: about \(bodyBudget.value) tokens",
        value: $bodyBudget.value,
        in: ClassificationLimits.bodyTokenBudgetRange,
        step: Self.bodyTokenBudgetStep
      )
    } header: {
      Text("Classification context")
    } footer: {
      Text(
        """
        More context can improve decisions but costs more with paid providers. Quoted replies are \
        shortened, and attachment text is included only when you turn it on.
        """
      )
      .foregroundStyle(.secondary)
    }
  }
}

/// Rarely needed details and the disposable-message move test, behind one disclosure.
private struct DiagnosticsSection: View {
  let model: AppModel

  var body: some View {
    Section {
      DisclosureGroup("Diagnostics") {
        LabeledContent("Mail access", value: model.settings.settings.incomingRoute.localizedTitle)
        LabeledContent("Pending retries", value: model.shared.state.retries.count.formatted())
        if model.settings.settings.advancedOptions.transport == .appleMail {
          MoveTestView(mail: model.mail)
        }
      }
    }
  }
}

private struct MoveTestView: View {
  let mail: MailConnectionModel

  private var settlingTime: String {
    AppleMailAdapter.defaultMoveSettlingTime.formatted(.units(allowed: [.seconds], width: .wide))
  }

  var body: some View {
    LabeledContent {
      HStack {
        if mail.moveTest.isBusy { ProgressView().controlSize(.small) }
        Button("Test selected message") { mail.testDisposableMessage() }
          .disabled(mail.moveTest.isBusy)
      }
    } label: {
      Text("Move test")
      Text(
        """
        Select one Inbox message whose subject begins “[SpamWise Probe]”. SpamWise moves it to \
        Junk and back, then flags it orange, waiting up to \(settlingTime) for Mail to show each \
        move. Dry run isn’t changed.
        """
      )
    }
    OperationStatusView(operation: mail.moveTest)
  }
}

#Preview("Advanced") { AdvancedSettingsView(model: PreviewHelper.model()) }
#Preview("Move test") {
  Form { MoveTestView(mail: PreviewHelper.model().mail) }.formStyle(.grouped)
}
