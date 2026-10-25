import SpamWiseCore

/**
 What SpamWise is doing with incoming mail, as the menu bar and Activity footer report it.

 It refines ``FilteringStatus`` with conditions only the running app observes: whether the
 network a check needs is reachable and whether recent checks failed. States are listed from
 most to least limiting, and the most limiting one is shown.
 */
enum FilteringState: String, CaseIterable {
  /// Setup has not been finished.
  case setupIncomplete
  /// The user paused filtering.
  case paused
  /// Apple Mail has not granted Automation.
  case mailNotAuthorized
  /// Apple Mail is not running.
  case mailNotRunning
  /// The network that checks need is unreachable.
  case offline
  /// The latest check of some account or folder failed or keeps timing out.
  case failing
  /// Dry run, with no Inbox and Junk mailboxes validated yet for an account of the selected
  /// transport.
  case rolesNotValidated
  /// Dry run: decisions are recorded but mail is unchanged.
  case dryRun
  /// Live filtering of validated accounts.
  case filtering

  /**
   Combines the configured status with what the app observes.

   - Parameters:
     - status: The status that settings and Mail Automation determine.
     - needsNetwork: Whether checks reach a mail server or a remote model.
     - isOnline: Whether the network is reachable.
     - isFailing: Whether recent checks failed.
   */
  init(_ status: FilteringStatus, needsNetwork: Bool, isOnline: Bool, isFailing: Bool) {
    let checking = status.allowsAutomaticChecks
    self =
      switch status {
        case _ where checking && needsNetwork && !isOnline: .offline
        case _ where checking && isFailing: .failing
        case .setupIncomplete: .setupIncomplete
        case .paused: .paused
        case .mailNotAuthorized: .mailNotAuthorized
        case .mailNotRunning: .mailNotRunning
        case .rolesNotValidated: .rolesNotValidated
        case .dryRun: .dryRun
        case .filtering: .filtering
      }
  }
}

extension Settings {
  /// Whether checking mail reaches a mail server or a remote model.
  var checksNeedNetwork: Bool {
    advancedOptions.transport == .imap || advancedOptions.backend != .onDevice
  }
}
