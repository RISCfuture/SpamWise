/// Mail Automation consent and availability, read without prompting or launching Mail.
public enum MailAutomationStatus: Sendable, Equatable {
  /// Not read yet.
  case unknown
  /// SpamWise may control Mail.
  case granted
  /// The user denied Automation or has not answered the prompt yet.
  case notAuthorized
  /// Mail is not running, so consent cannot be read and no script runs.
  case mailNotRunning
}

/// What SpamWise is currently doing with incoming mail, most limiting state first.
public enum FilteringStatus: String, Sendable, CaseIterable {
  /// Setup has not been finished.
  case setupIncomplete
  /// The user paused filtering.
  case paused
  /// Apple Mail has not granted Automation.
  case mailNotAuthorized
  /// Apple Mail is not running.
  case mailNotRunning
  /// Only the Mail extension previews incoming mail; nothing moves.
  case extensionPreview
  /// The Mail extension route is chosen, but account scope stops it from previewing mail.
  case extensionScoped
  /// Dry run, with no account's Inbox and Junk mailboxes validated yet.
  case rolesNotValidated
  /// Dry run: decisions are recorded but mail is unchanged.
  case dryRun
  /// Live filtering of validated accounts.
  case filtering

  /// Whether automatic Inbox checks may run, in dry run or live.
  public var allowsAutomaticChecks: Bool {
    [.rolesNotValidated, .dryRun, .filtering].contains(self)
  }

  /// Derives the status from settings and, for Apple Mail, the current Automation state.
  public init(settings: Settings, mailAutomation: MailAutomationStatus) {
    let appleMail = settings.advancedOptions.transport == .appleMail
    self =
      if !settings.onboardingComplete {
        .setupIncomplete
      } else if settings.paused {
        .paused
      } else if appleMail, mailAutomation == .notAuthorized {
        .mailNotAuthorized
      } else if appleMail, mailAutomation == .mailNotRunning {
        .mailNotRunning
      } else if settings.incomingRoute == .mailKit {
        MailExtensionPreview.allows(settings) ? .extensionPreview : .extensionScoped
      } else if settings.dryRun {
        settings.validatedAccounts.isEmpty ? .rolesNotValidated : .dryRun
      } else {
        .filtering
      }
  }
}

extension StateRepository {
  /// Records read-only Inbox and Junk role checks keyed by account.
  ///
  /// Accounts whose roles resolved uniquely become validated; others lose validation.
  /// Dry run turns back on when no validated account remains.
  /// - Parameters:
  ///   - unambiguousByAccount: Whether each checked account's roles resolved uniquely.
  ///   - store: The shared state store.
  ///   - currentAccounts: Every account the mail client currently reports, when known.
  ///     Validated accounts missing from it lose validation.
  public static func recordMailboxRoles(
    _ unambiguousByAccount: [String: Bool],
    in store: Store,
    currentAccounts: Set<String>? = nil
  ) async throws {
    try await update(store, loading: StateSlices()) { state in
      if let currentAccounts {
        state.settings.validatedAccounts.formIntersection(currentAccounts)
      }
      for (account, unambiguous) in unambiguousByAccount {
        if unambiguous {
          state.settings.validatedAccounts.insert(account)
        } else {
          state.settings.validatedAccounts.remove(account)
        }
      }
      if state.settings.validatedAccounts.isEmpty { state.settings.dryRun = true }
    }
  }
}
