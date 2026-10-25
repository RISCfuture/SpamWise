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
  func `rejects an archive with an invalid rule`() {
    let invalid = Data(
      #"{"version":1,"rules":[{"scope":"domain","value":"com","disposition":"block","updatedAt":0}]}"#
        .utf8
    )
    #expect(throws: RuleManagementError.invalidRule) {
      try RuleManagement.previewImport(invalid, against: saved.rules)
    }
  }

  @Test
  func `previews and imports exported rules with their identities`() async throws {
    let other = try testStore()
    try await RuleManagement.save(
      scope: .address,
      value: "person@example.com",
      disposition: .block,
      store: other
    )
    let shop = SenderRule(scope: .domain, value: "shop.example", disposition: .block)
    let archive = try RuleManagement.exportRules(saved.rules + [shop])
    let preview = try RuleManagement.previewImport(
      archive,
      against: try await StateRepository.load(other).rules
    )
    #expect(preview.added == 1)
    #expect(preview.replaced == 1)
    #expect(preview.unchanged == 0)
    #expect(preview.blocksToAllow == ["person@example.com"])
    try await RuleManagement.commitImport(preview, store: other)
    let imported = try await StateRepository.load(other).rules
    #expect(Set(imported.map(\.id)) == Set((saved.rules + [shop]).map(\.id)))
    #expect(imported.allSatisfy { $0.disposition == ($0.id == shop.id ? .block : .allow) })
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
