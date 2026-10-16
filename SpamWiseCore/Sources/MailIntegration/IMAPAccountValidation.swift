import Foundation
public import SpamWiseCore

/// Whose IMAP validation evidence a check records and an adapter's actions require.
public enum IMAPValidationScope: String, Sendable, CaseIterable {
  /// The app's saved connection; recording its validation also selects the app's IMAP transport.
  case app
  /// The headless daemon; recording its validation never changes the app's route or transport.
  case daemon

  var evidenceKey: String {
    switch self {
      case .app: "imap-probe-validations-v1"
      case .daemon: "imap-daemon-validations-v1"
    }
  }
}

/// Binds a successful mailbox validation to its exact endpoint, account and authentication identity.
public enum IMAPAccountValidation {
  /**
   Saves validation evidence for `scope` and adds the account to the shared validated accounts.

   Under ``IMAPValidationScope/app`` this also selects the IMAP transport, so the app's sweeps
   and its incoming route switch to IMAP. Under ``IMAPValidationScope/daemon`` the route and
   transport stay unchanged. Call only after observing a unique Junk mailbox with MOVE support,
   or a probe message restored to Inbox.
   */
  public static func record(
    _ configuration: IMAPConfiguration,
    scope: IMAPValidationScope = .app,
    store: Store
  ) async throws {
    try await store.update(scope.evidenceKey, default: [String: String]()) {
      $0[configuration.id] = configuration.endpointFingerprint
    }
    try await StateRepository.editSettings(store) { settings in
      settings.validatedAccounts.insert(configuration.id)
      guard scope == .app else { return }
      var advanced = settings.advancedOptions
      advanced.transport = .imap
      settings.advancedOptions = advanced
    }
  }
  /**
   Records validation when a read-only check found MOVE support and a unique Junk mailbox,
   and revokes it otherwise.

   See ``record(_:scope:store:)`` and ``revoke(_:scope:store:)`` for the settings each changes.

   - Returns: Whether the account is validated after the check.
   */
  @discardableResult
  public static func record(
    _ check: IMAPValidation,
    for configuration: IMAPConfiguration,
    scope: IMAPValidationScope = .app,
    store: Store
  ) async throws -> Bool {
    guard check.movesToJunk else {
      try await revoke(configuration, scope: scope, store: store)
      return false
    }
    try await record(configuration, scope: scope, store: store)
    return true
  }
  /// The accounts with saved validation evidence in any scope.
  static func accountIDs(in store: Store) async throws -> Set<String> {
    var accounts: Set<String> = []
    for scope in IMAPValidationScope.allCases {
      accounts.formUnion(try await store.read(scope.evidenceKey, default: [String: String]()).keys)
    }
    return accounts
  }
  /**
   Removes the scope's validation evidence.

   The account leaves the shared validated accounts unless another scope still holds evidence
   for it; dry run turns back on when no validated account remains.
   */
  public static func revoke(
    _ configuration: IMAPConfiguration,
    scope: IMAPValidationScope = .app,
    store: Store
  ) async throws {
    try await store.update(scope.evidenceKey, default: [String: String]()) {
      $0[configuration.id] = nil
    }
    guard try await !accountIDs(in: store).contains(configuration.id) else { return }
    try await StateRepository.recordMailboxRoles([configuration.id: false], in: store)
  }
  /**
   Requires the scope's persisted endpoint evidence and the shared validated-account gate.

   The app scope also requires the IMAP incoming route.
   */
  public static func isValidated(
    _ configuration: IMAPConfiguration,
    scope: IMAPValidationScope = .app,
    store: Store
  ) async throws -> Bool {
    let validations = try await store.read(scope.evidenceKey, default: [String: String]())
    let settings = try await StateRepository.load(store, StateSlices()).settings
    return validations[configuration.id] == configuration.endpointFingerprint
      && settings.validatedAccounts.contains(configuration.id)
      && (scope == .daemon || settings.incomingRoute == .imap)
  }
}
