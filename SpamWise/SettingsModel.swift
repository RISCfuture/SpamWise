import Network
import SwiftUI
import SpamWiseCore

/**
 Edits shared settings optimistically: an edit shows at once and its write is queued after every
 earlier one, so rapid edits persist in order and a reload never shows a stale value meanwhile.

 Each control writes only its own field. Steppers and text fields edit through a
 ``SettingDraft``, so a burst of clicks or keystrokes makes one write.
 */
@MainActor
@Observable
final class SettingsModel {
  private static let stepperDelay: Duration = .milliseconds(600)
  private static let textDelay: Duration = .milliseconds(1500)
  /// The latest settings write failure, until the next write succeeds.
  var saveFailure: OperationFailure?
  /// Why the latest spending-limit change was refused.
  var spendingLimitError: String?
  @ObservationIgnored private let shared: SharedStateModel
  @ObservationIgnored private var tail: Task<Void, Never>?
  /// The additional instructions, saved after a pause in typing; text over the limit stays unsaved.
  @ObservationIgnored private(set) lazy var policy = SettingDraft(
    delay: Self.textDelay,
    persisted: { [shared] in shared.state.settings.policy },
    accepts: { $0.count <= ClassificationLimits.maximumPolicyCharacters },
    save: { [weak self] in self?.setSetting(\.policy, to: $0) }
  )
  /// How many similar corrections accompany each message.
  @ObservationIgnored private(set) lazy var correctionLimit = SettingDraft(
    delay: Self.stepperDelay,
    persisted: { [shared] in shared.state.settings.correctionLimit },
    save: { [weak self] in self?.setSetting(\.correctionLimit, to: $0) }
  )
  /// How much message text accompanies each message, in estimated tokens.
  @ObservationIgnored private(set) lazy var bodyTokenBudget = SettingDraft(
    delay: Self.stepperDelay,
    persisted: { [shared] in shared.state.settings.bodyTokenBudget },
    save: { [weak self] in self?.setSetting(\.bodyTokenBudget, to: $0) }
  )
  /// The shortest time between notifications, in minutes.
  @ObservationIgnored private(set) lazy var notificationIntervalMin = SettingDraft(
    delay: Self.stepperDelay,
    persisted: { [shared] in shared.state.settings.mailOptions.notifications.intervalMin },
    save: { [weak self] in self?.setSetting(\.mailOptions.notifications.intervalMin, to: $0) }
  )
  /// The DNS resolver for public Spamhaus lookups; only an IPv4 address is saved.
  @ObservationIgnored private(set) lazy var resolverAddress = SettingDraft(
    delay: Self.textDelay,
    persisted: { [shared] in Self.evidence(in: shared.state.settings).resolverAddress },
    accepts: { IPv4Address($0) != nil },
    save: { [weak self] address in self?.editEvidence { $0.resolverAddress = address } }
  )

  var settings: SpamWiseCore.Settings { shared.state.settings }
  /// The optional evidence configuration, or its disabled defaults.
  var evidence: ExternalEvidenceSettings { Self.evidence(in: settings) }
  /// Whether local-only mode is on while a network provider is still selected.
  var hasLocalOnlyConflict: Bool {
    settings.mailOptions.localOnly && settings.advancedOptions.backend != .onDevice
  }

  init(shared: SharedStateModel) { self.shared = shared }

  private static func evidence(in settings: SpamWiseCore.Settings) -> ExternalEvidenceSettings {
    settings.advancedOptions.externalEvidence ?? ExternalEvidenceSettings()
  }

  /// Applies `edit` locally, then persists it after every earlier settings write; a failed write
  /// puts the stored settings back once no other write is pending.
  @discardableResult
  func editSettings(
    _ edit: @escaping @Sendable (inout SpamWiseCore.Settings) -> Void
  ) -> Task<Void, Never> {
    guard let store = shared.store else { return Task {} }
    edit(&shared.state.settings)
    shared.settingsWritesInFlight += 1
    return enqueueWrite { [self] in
      defer { shared.settingsWritesInFlight -= 1 }
      do {
        try await StateRepository.editSettings(store, edit)
        saveFailure = nil
      } catch {
        shared.reloadSettingsAfterFailedWrite()
        saveFailure = OperationFailure(
          message: String(localized: "Settings could not be saved; mail stays unchanged.")
        )
      }
    }
  }

  @discardableResult
  func setSetting<T: Sendable>(
    _ key: any WritableKeyPath<SpamWiseCore.Settings, T> & Sendable,
    to value: T
  ) -> Task<Void, Never> {
    editSettings { $0[keyPath: key] = value }
  }

  /// Turns local-only mode on, selecting the on-device model in the same write.
  func keepFilteringOnThisMac() {
    editSettings {
      $0.mailOptions.localOnly = true
      if $0.advancedOptions.backend != .onDevice {
        $0.advancedOptions.select(ModelBackend.onDevice.defaultModel)
      }
    }
  }

  /// Turns local-only mode off; the selected provider is unchanged.
  func allowNetworkProviders() {
    setSetting(\.mailOptions.localOnly, to: false)
  }

  /// Selects `backend` with its default model; reselecting the current provider keeps its model.
  func selectBackend(_ backend: ModelBackend) {
    guard backend != settings.advancedOptions.backend else { return }
    editSettings { $0.advancedOptions.select(backend.defaultModel) }
  }

  /// Selects `model` together with the provider that serves it.
  func selectModel(_ model: ModelIdentifier) {
    editSettings { $0.advancedOptions.select(model) }
  }

  /// Grants or withdraws `backend`'s permission to receive mail context.
  func setSharingConsent(_ granted: Bool, for backend: ModelBackend) {
    editSettings {
      if granted {
        $0.advancedOptions.mailSharingConsent.insert(backend)
      } else {
        $0.advancedOptions.mailSharingConsent.remove(backend)
      }
    }
  }

  /// Selects the Spamhaus service, withdrawing acceptance of the previous service's terms.
  func selectSpamhausService(_ transport: SpamhausTransport) {
    editEvidence {
      guard $0.spamhausTransport != transport else { return }
      $0.spamhausTransport = transport
      $0.termsAcknowledged = false
    }
  }

  /// Clears the additional instructions and restores every category preference, at once.
  func resetPreferences() {
    policy.value = PromptBuilder.defaultPolicy
    policy.commit()
    setSetting(\.categoryPreferences, to: .defaults)
  }

  func togglePause() {
    setSetting(\.paused, to: !settings.paused)
  }

  /// Completes onboarding, keeping dry run on the first time.
  func completeOnboarding() {
    editSettings {
      if !$0.onboardingComplete { $0.dryRun = true }
      $0.onboardingComplete = true
    }
  }

  /// Saves every acceptable edit still waiting in a draft, then waits for all queued writes.
  func savePendingEdits() async {
    policy.commit()
    correctionLimit.commit()
    bodyTokenBudget.commit()
    notificationIntervalMin.commit()
    resolverAddress.commit()
    await tail?.value
  }

  /// Sets or removes the monthly spending limit, in order with settings writes.
  func setSpendingLimit(usd: Double?) {
    guard let store = shared.store else { return }
    enqueueWrite { [self] in
      do {
        try await SpendingLimit.setLimit(usd: usd, store: store)
        spendingLimitError = nil
      } catch {
        spendingLimitError = OperationFailure.describe(error)
      }
    }
  }

  func binding<T: Sendable>(_ key: any WritableKeyPath<SpamWiseCore.Settings, T> & Sendable)
    -> Binding<T>
  {
    Binding(get: { self.settings[keyPath: key] }, set: { self.setSetting(key, to: $0) })
  }

  func mailBinding<T: Sendable>(
    _ key: any WritableKeyPath<MailPreferences, T> & Sendable
  ) -> Binding<T> {
    Binding(
      get: { self.settings.mailOptions[keyPath: key] },
      set: { value in self.editSettings { $0.mailOptions[keyPath: key] = value } }
    )
  }

  func advancedBinding<T: Sendable>(
    _ key: any WritableKeyPath<AdvancedSettings, T> & Sendable
  ) -> Binding<T> {
    Binding(
      get: { self.settings.advancedOptions[keyPath: key] },
      set: { value in
        self.editSettings {
          var advanced = $0.advancedOptions; advanced[keyPath: key] = value
          $0.advancedOptions = advanced
        }
      }
    )
  }

  /// A binding that writes one optional-evidence field, creating the configuration if needed.
  func evidenceBinding<T: Sendable>(
    _ key: any WritableKeyPath<ExternalEvidenceSettings, T> & Sendable
  ) -> Binding<T> {
    Binding(
      get: { self.evidence[keyPath: key] },
      set: { value in self.editEvidence { $0[keyPath: key] = value } }
    )
  }

  private func editEvidence(
    _ edit: @escaping @Sendable (inout ExternalEvidenceSettings) -> Void
  ) {
    editSettings {
      var evidence = $0.advancedOptions.externalEvidence ?? ExternalEvidenceSettings()
      edit(&evidence)
      $0.advancedOptions.externalEvidence = evidence
    }
  }

  /// Runs `write` after every earlier settings write, then reloads shared storage.
  @discardableResult
  private func enqueueWrite(
    _ write: @escaping @MainActor () async -> Void
  ) -> Task<Void, Never> {
    let previous = tail
    let task = Task { [shared] in
      await previous?.value
      await write()
      await shared.refresh()
    }
    tail = task
    return task
  }
}
