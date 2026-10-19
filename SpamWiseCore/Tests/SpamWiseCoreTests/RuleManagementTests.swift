import Foundation
import Testing
import SpamWiseCore

@Suite
struct `Sender rule management` {
  private let store: Store
  /// State after saving one address Allow rule for `Person@Example.com`.
  private let saved: AppState

  init() async throws {
    store = try testStore()
    try await RuleManagement.save(
      scope: .address,
      value: "Person@Example.com",
      disposition: .allow,
      store: store
    )
    saved = try await StateRepository.load(store)
  }

  @Test
  func `normalizes saved addresses to lowercase`() {
    #expect(saved.rules.map(\.value) == ["person@example.com"])
  }

  @Test
  func `rejects an import with an invalid rule without changing rules or audit`() async throws {
    let invalid = Data(
      #"{"version":1,"rules":[{"scope":"domain","value":"com","disposition":"block","updatedAt":0}]}"#
        .utf8
    )
    await #expect(throws: RuleManagementError.self) {
      try await RuleManagement.importRules(invalid, store: store)
    }
    let state = try await StateRepository.load(store)
    #expect(state.rules == saved.rules)
    #expect(state.auditEvents.count == saved.auditEvents.count)
  }

  @Test
  func `imports exported rules with their identities`() async throws {
    let other = try testStore()
    try await RuleManagement.importRules(RuleManagement.exportRules(saved.rules), store: other)
    #expect(try await StateRepository.load(other).rules.map(\.id) == saved.rules.map(\.id))
  }

  @Test
  func `replaces the same-scope rule and invalidates stale work`() async throws {
    try await RuleManagement.save(
      scope: .address,
      value: "person@example.com",
      disposition: .block,
      store: store
    )
    let changed = try await StateRepository.load(store)
    #expect(changed.rules.map(\.disposition) == [.block])
    #expect(changed.revision > saved.revision)
    #expect(changed.auditEvents.last?.kind == .senderRule)
  }
}
