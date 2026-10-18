public import Foundation

/// Atomic editing of bounded content rules; sender rules always retain precedence.
public enum ContentRuleManagement {
  private static let maximumRules = RetentionLimits.contentRules
  private static let maximumArchiveBytes = 1_000_000
  /// Exports versioned content rules without message samples or credentials.
  public static func exportRules(_ rules: [ContentRule]) throws -> Data {
    try validate(rules)
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(Archive(rules: rules))
  }
  /// Validates the complete archive before merging rules by identity and invalidating old work.
  public static func importRules(_ data: Data, store: Store) async throws {
    guard data.count <= maximumArchiveBytes else { throw ContentRuleError.invalid }
    let archive = try JSONDecoder().decode(Archive.self, from: data)
    guard archive.version == 1 else { throw ContentRuleError.invalid }
    try validate(archive.rules)
    try await StateRepository.update(store, loading: StateSlices([.contentRules])) { state in
      let importedIDs = Set(archive.rules.map(\.id))
      let combined = state.contentRules.filter { !importedIDs.contains($0.id) } + archive.rules
      try validate(combined)
      state.contentRules = combined
      for id in importedIDs { state.contentRuleSkips[id] = nil }
      state.invalidatePendingWork(.contentRulesImported(count: archive.rules.count))
    }
  }
  private static func validate(_ rules: [ContentRule]) throws {
    guard rules.count <= maximumRules, Set(rules.map(\.id)).count == rules.count else {
      throw ContentRuleError.invalid
    }
    for rule in rules { try ContentRules.validate(rule) }
  }
  /// Saves an explicit staged rule and invalidates older pending classifications.
  public static func save(_ rule: ContentRule, store: Store) async throws {
    try ContentRules.validate(rule)
    var updated = rule; updated.updatedAt = .now
    let saved = updated
    try await StateRepository.update(store, loading: StateSlices([.contentRules])) { state in
      state.contentRules.removeAll { $0.id == saved.id }
      state.contentRules.append(saved)
      guard state.contentRules.count <= maximumRules else { throw ContentRuleError.invalid }
      state.contentRuleSkips[saved.id] = nil
      state.invalidatePendingWork(
        .contentRuleSaved(
          field: saved.field,
          pattern: saved.pattern,
          disposition: saved.disposition
        )
      )
    }
  }
  /// Removes one rule without modifying mail or other rules.
  public static func remove(_ id: UUID, store: Store) async throws {
    try await StateRepository.update(store, loading: StateSlices([.contentRules])) { state in
      guard let rule = state.contentRules.first(where: { $0.id == id }) else { return }
      state.contentRules.removeAll { $0.id == id }
      state.contentRuleSkips[id] = nil
      state.invalidatePendingWork(.contentRuleRemoved(field: rule.field, pattern: rule.pattern))
    }
  }
  private struct Archive: Codable { var version = 1; var rules: [ContentRule] }
}
