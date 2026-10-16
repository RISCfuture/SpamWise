public import Foundation

/// Atomic editing of bounded content rules; sender rules always retain precedence.
public enum ContentRuleManagement {
  private static let maximumRules = 100
  /// Saves an explicit staged rule and invalidates older pending classifications.
  public static func save(_ rule: ContentRule, store: Store) async throws {
    try ContentRules.validate(rule)
    var updated = rule; updated.updatedAt = .now
    let saved = updated
    try await StateRepository.update(store) { state in
      var rules = state.contentRules ?? []
      rules.removeAll { $0.id == saved.id }
      rules.append(saved)
      guard rules.count <= maximumRules else { throw ContentRuleError.invalid }
      state.contentRules = rules
      state.revision += 1; state.retries.removeAll()
    }
  }
  /// Removes one rule without modifying mail or other rules.
  public static func remove(_ id: UUID, store: Store) async throws {
    try await StateRepository.update(store) {
      $0.contentRules?.removeAll { $0.id == id }
      $0.revision += 1; $0.retries.removeAll()
    }
  }
}
