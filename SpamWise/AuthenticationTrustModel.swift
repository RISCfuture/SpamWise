import Foundation
import Observation
import SpamWiseCore

/**
 Each account's trusted receiving mail servers, which let SpamWise check senders' authentication.

 Until an account trusts a server, Contacts, correspondence history and Allow rules only inform
 the classifier for that account's mail.
 */
@MainActor @Observable final class AuthenticationTrustModel {
  /// Trusted servers and detection progress by account identifier.
  var accounts: [String: AccountAuthentication] = [:]
  /// Reading every account's trust; its failure explains an empty or stale list.
  let loading = TrackedOperation()
  @ObservationIgnored private let services: AppServices
  @ObservationIgnored private let shared: SharedStateModel
  @ObservationIgnored private var operations: [String: TrackedOperation] = [:]

  init(services: AppServices, shared: SharedStateModel) {
    self.services = services
    self.shared = shared
  }

  /// The server names in `text`, separated by commas, spaces or new lines.
  nonisolated static func servers(in text: String) -> [String] {
    text.split { $0 == "," || $0.isWhitespace }.map(String.init)
  }

  /// Rereads every account's trusted servers and detection progress.
  func refresh() async {
    guard let store = services.store else { return }
    await loading.run(retryable: true) { [self] in
      let loaded = try await AuthenticationTrust.accounts(store)
      if loaded != accounts { accounts = loaded }
      return nil
    }.value
  }

  /// Confirming, editing or clearing `accountID`'s trusted servers.
  func operation(for accountID: String) -> TrackedOperation {
    if let operation = operations[accountID] { return operation }
    let operation = TrackedOperation()
    operations[accountID] = operation
    return operation
  }

  /// Trusts the servers detected in the account's mail.
  func confirmDetected(accountID: String) {
    change(accountID) { store in
      try await AuthenticationTrust.confirmDetected(accountID: accountID, store: store)
    }
  }

  /// Replaces the account's trusted servers with those listed in `text`.
  @discardableResult func save(_ text: String, accountID: String) -> Task<Void, Never> {
    let servers = Self.servers(in: text)
    return change(accountID) { store in
      try await AuthenticationTrust.save(servers, accountID: accountID, store: store)
    }
  }

  /// Stops trusting any server for the account.
  func stopTrusting(accountID: String) {
    change(accountID) { store in
      try await AuthenticationTrust.save([], accountID: accountID, store: store)
    }
  }

  @discardableResult private func change(
    _ accountID: String,
    _ edit: @escaping @MainActor (Store) async throws -> Void
  ) -> Task<Void, Never> {
    operation(for: accountID).run { [self] in
      try await edit(services.requireStore())
      await refresh()
      await shared.refresh()
      return nil
    }
  }
}
