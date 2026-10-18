import SwiftUI
import SpamWiseCore

/**
 Edits shared settings optimistically: an edit shows at once and its write is queued after every
 earlier one, so rapid edits persist in order and a reload never shows a stale value meanwhile.
 */
@MainActor @Observable final class SettingsModel {
  /// The latest settings write failure, until the next write succeeds.
  var saveFailure: OperationFailure?
  /// Why the latest spending-limit change was refused.
  var spendingLimitError: String?
  @ObservationIgnored private let shared: SharedStateModel
  @ObservationIgnored private var tail: Task<Void, Never>?

  var settings: SpamWiseCore.Settings { shared.state.settings }

  init(shared: SharedStateModel) { self.shared = shared }

  /// Applies `edit` locally, then persists it after every earlier settings write.
  @discardableResult func editSettings(
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
        saveFailure = OperationFailure(
          message: String(localized: "Settings could not be saved; mail stays unchanged.")
        )
      }
    }
  }

  @discardableResult func setSetting<T: Sendable>(
    _ key: any WritableKeyPath<SpamWiseCore.Settings, T> & Sendable,
    to value: T
  ) -> Task<Void, Never> {
    editSettings { $0[keyPath: key] = value }
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

  /// Selects `backend` with its default model; reselecting the current provider keeps its model.
  func selectBackend(_ backend: ModelBackend) {
    guard backend != settings.advancedOptions.backend else { return }
    editSettings {
      var advanced = $0.advancedOptions
      advanced.select(backend.defaultModel)
      $0.advancedOptions = advanced
    }
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

  /// Runs `write` after every earlier settings write, then reloads shared storage.
  @discardableResult private func enqueueWrite(
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
