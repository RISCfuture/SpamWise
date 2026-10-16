import AppKit
import Observation
import SpamWiseCore
import MailIntegration

/// The Apple Mail connection: Automation permission, accounts and their mailbox roles.
@MainActor
@Observable
final class MailConnectionModel {
  /// Accounts Mail reported at the latest discovery.
  var accounts: [MailAccount] = []
  /// Whether Mail Automation is allowed, as last read without prompting.
  var automation = MailAutomationStatus.unknown
  /// Whether the latest connection check was refused Automation permission.
  var permissionDenied = false
  /// Checking the connection: permission, accounts and mailbox roles.
  let check = TrackedOperation()
  /// The optional disposable-message move test.
  let moveTest = TrackedOperation()
  @ObservationIgnored private let services: AppServices
  @ObservationIgnored private let shared: SharedStateModel

  init(services: AppServices, shared: SharedStateModel) {
    self.services = services
    self.shared = shared
    #if DEBUG
      if services.uiTesting {
        accounts = [
          MailAccount(id: "ui-test", name: "Example account", addresses: ["me@example.org"])
        ]
      }
    #endif
  }

  /// Requests Automation permission, then discovers accounts and validates their mailboxes.
  func checkConnection() {
    check.run(retryable: true) { [self] in
      permissionDenied = false
      do {
        if services.uiTesting { throw IntegrationError.permissionDenied }
        try await SystemAppleEventRunner.requestMailPermission()
        automation = .granted
        try await discoverAccounts()
        let validated = try await validateMailboxRoles()
        return String(
          localized:
            "Connected to Mail. Found the Inbox and Junk mailboxes for \(validated) of \(accounts.count) accounts."
        )
      } catch IntegrationError.permissionDenied {
        permissionDenied = true
        automation = .notAuthorized
        throw IntegrationError.permissionDenied
      }
    }
  }

  /// Rereads Automation permission without prompting, when Apple Mail is the selected transport.
  func refreshAutomationStatus() async {
    let settings = shared.settings
    guard !services.uiTesting, settings.onboardingComplete,
      settings.advancedOptions.transport == .appleMail
    else { return }
    automation = await SystemAppleEventRunner.mailAutomationStatus()
  }

  /// Reads Mail's accounts and records their addresses as the user's own.
  func discoverAccounts() async throws {
    let discovered = try await services.appleMail.accounts()
    accounts = discovered
    guard let store = services.store else { return }
    let addresses = Set(discovered.flatMap(\.addresses))
    try await StateRepository.update(store, loading: StateSlices([.contacts])) {
      $0.ownAddresses = addresses
    }
  }

  /**
   Reads each discovered account's Inbox and Junk roles and records the definitive results.

   An account whose check fails keeps its previous validation, and an account Mail no longer
   reports loses it while validated IMAP accounts keep theirs. Returns the validated count.
   */
  func validateMailboxRoles() async throws -> Int {
    var results: [String: Bool] = [:]
    for account in accounts {
      try Task.checkCancellation()
      if let destinations = try? await services.appleMail.destinations(accountID: account.id) {
        results[account.id] = destinations.isUnambiguous
      }
    }
    if let store = services.store {
      try await StateRepository.recordAppleMailRoles(
        results,
        in: store,
        reportedAccounts: Set(accounts.map(\.id))
      )
    }
    return accounts.count { results[$0.id] ?? shared.settings.validatedAccounts.contains($0.id) }
  }

  /// Reads one account's mailbox roles and records whether they resolve uniquely.
  func readDestinations(accountID: String) async throws -> MailDestinations {
    let destinations = try await services.appleMail.destinations(accountID: accountID)
    if let store = services.store {
      try await StateRepository.recordMailboxRoles(
        [accountID: destinations.isUnambiguous],
        in: store
      )
    }
    return destinations
  }

  /// Moves the selected disposable probe to Junk and back, then flags it.
  func testDisposableMessage() {
    moveTest.run { [self] in
      _ = try await services.appleMail.testDisposableMessage()
      return String(localized: "Junk, Inbox restoration, and orange flag verified in Mail.")
    }
  }

  /// Shows the bundled Mail rule script in Finder.
  func revealRuleScript() throws {
    guard let url = Bundle.main.url(forResource: "SpamWiseRule", withExtension: "scpt") else {
      throw RuleScriptError.missing
    }
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }
}

/// The Mail rule script is missing from the app bundle.
enum RuleScriptError: LocalizedError {
  case missing

  var errorDescription: String? { String(localized: "Couldn’t show the Mail rule script.") }
  var failureReason: String? { String(localized: "The script is missing from the SpamWise app.") }
  var recoverySuggestion: String? { String(localized: "Reinstall SpamWise.") }
}
