import Foundation
import Testing
import SpamWiseCore

/// Settings after onboarding, still in dry run with no validated account.
private let onboarded: Settings = {
  var settings = Settings()
  settings.onboardingComplete = true
  return settings
}()

@Test(arguments: [
  (MailAutomationStatus.notAuthorized, FilteringStatus.mailNotAuthorized),
  (.mailNotRunning, .mailNotRunning), (.granted, .rolesNotValidated)
])
func `reports the most limiting status before any account is validated`(
  automation: MailAutomationStatus,
  status: FilteringStatus
) {
  let derived = FilteringStatus(settings: onboarded, mailAutomation: automation)
  #expect(derived == status)
  #expect(derived.allowsAutomaticChecks == (status == .rolesNotValidated))
}

@Test(arguments: [
  (["mail-account"], MailTransport.imap, FilteringStatus.rolesNotValidated),
  (["imap:account"], .appleMail, .rolesNotValidated),
  (["mail-account", "imap:account"], .imap, .dryRun)
])
func `counts only the selected transport's validated accounts`(
  validated: [String],
  transport: MailTransport,
  status: FilteringStatus
) {
  var settings = onboarded
  settings.validatedAccounts = Set(validated)
  settings.advancedOptions.transport = transport
  #expect(FilteringStatus(settings: settings, mailAutomation: .granted) == status)
}

@Test
func `stops automatic checks while paused`() {
  var paused = onboarded
  paused.paused = true
  #expect(!FilteringStatus(settings: paused, mailAutomation: .granted).allowsAutomaticChecks)
}

@Test
func `preserves safety settings and validated accounts during field edits`() async throws {
  let store = try testStore()
  try await enableActions(store)
  try await StateRepository.editSettings(store) {
    $0.paused = true; $0.dryRun = true
  }
  try await StateRepository.editSettings(store) {
    $0.strength = .aggressive; $0.bodyTokenBudget = 3000
  }
  let state = try await StateRepository.load(store)
  #expect(state.settings.paused)
  #expect(state.settings.dryRun)
  #expect(state.settings.validatedAccounts == ["account-A"])
  #expect(state.revision == 1)
  #expect(
    state.auditEvents.last?.change == .settingsChanged(fields: ["bodyTokenBudget", "strength"])
  )
}

@Test
func `clamps an edited body token budget to the supported maximum`() async throws {
  let store = try testStore()
  try await StateRepository.editSettings(store) { $0.bodyTokenBudget = 50_000 }
  #expect(try await StateRepository.load(store).settings.bodyTokenBudget == 4000)
}

@Suite
struct `Mailbox role validation` {
  private let store: Store

  /// Records account A's roles as unique and account B's as ambiguous, then turns off dry run.
  init() async throws {
    store = try testStore()
    try await StateRepository.update(store) { $0.settings.onboardingComplete = true }
    try await StateRepository.recordMailboxRoles(["account-A": true, "account-B": false], in: store)
    try await StateRepository.editSettings(store) { $0.dryRun = false }
  }

  private func settings() async throws -> Settings {
    try await StateRepository.load(store).settings
  }

  @Test
  func `validates only accounts whose roles resolved uniquely`() async throws {
    let settings = try await settings()
    #expect(settings.validatedAccounts == ["account-A"])
    #expect(FilteringStatus(settings: settings, mailAutomation: .granted) == .filtering)
  }

  @Test
  func `refuses actions in an account without validated roles`() async throws {
    let adapter = RecordingAdapter()
    var unvalidated = try envelope()
    unvalidated.identity.accountID = "account-B"
    let record = await Pipeline(store: store, classifier: junkClassifier)
      .process(unvalidated, adapter: adapter)
    #expect(record.outcome == .integrationUnavailable)
    #expect(await adapter.actions.isEmpty)
  }

  @Test
  func `drops removed and failed accounts and restores dry run when none remain`()
    async throws
  {
    try await StateRepository.recordMailboxRoles(["account-B": true], in: store)
    try await StateRepository.recordMailboxRoles(
      ["account-A": false],
      in: store,
      currentAccounts: ["account-A"]
    )
    let settings = try await settings()
    #expect(settings.validatedAccounts.isEmpty)
    #expect(settings.dryRun)
  }
}
