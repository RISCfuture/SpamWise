public import Foundation

/// Atomic editing of bounded content rules; sender rules always retain precedence.
public enum ContentRuleManagement {
  private static let maximumRules = RetentionLimits.contentRules
  /// The largest content-rule archive, in bytes, that SpamWise imports.
  public static let maximumArchiveBytes = 1_000_000
  /// Exports versioned content rules without message samples or credentials.
  public static func exportRules(_ rules: [ContentRule]) throws -> Data {
    try validate(rules)
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(Archive(rules: rules))
  }
  /// Validates the complete archive before merging rules by identity and invalidating old work.
  public static func importRules(_ data: Data, store: Store) async throws {
    guard data.count <= maximumArchiveBytes else { throw ContentRuleError.invalidArchive }
    let archive: Archive
    do { archive = try JSONDecoder().decode(Archive.self, from: data) } catch {
      throw ContentRuleError.invalidArchive
    }
    guard archive.version == 1 else { throw ContentRuleError.invalidArchive }
    try validate(archive.rules)
    try await StateRepository.update(store, loading: StateSlices([.contentRules])) { state in
      let importedIDs = Set(archive.rules.map(\.id))
      let combined = state.contentRules.filter { !importedIDs.contains($0.id) } + archive.rules
      try validate(combined)
      state.contentRules = combined
      for id in importedIDs {
        state.contentRuleHits[id] = nil; state.contentRuleSkips[id] = nil
      }
      state.invalidatePendingWork(.contentRulesImported(count: archive.rules.count))
    }
  }
  /// Requires at most the retained number of valid rules, each with a distinct identity.
  static func validate(_ rules: [ContentRule]) throws {
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
      let stored = state.contentRules.first { $0.id == saved.id }
      if stored?.field != saved.field || stored?.operation != saved.operation
        || stored?.pattern != saved.pattern
      {
        state.contentRuleHits[saved.id] = nil
      }
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
  /**
   Turns one rule on or off without changing its edit date, so its precedence among matching
   rules stays the same; pending classifications are invalidated.
   */
  public static func setEnabled(_ id: UUID, _ enabled: Bool, store: Store) async throws {
    try await StateRepository.update(store, loading: StateSlices([.contentRules])) { state in
      guard let index = state.contentRules.firstIndex(where: { $0.id == id }),
        state.contentRules[index].enabled != enabled
      else { return }
      state.contentRules[index].enabled = enabled
      let rule = state.contentRules[index]
      state.invalidatePendingWork(
        .contentRuleSaved(field: rule.field, pattern: rule.pattern, disposition: rule.disposition)
      )
    }
  }
  /// Removes one rule without modifying mail or other rules.
  public static func remove(_ id: UUID, store: Store) async throws {
    try await StateRepository.update(store, loading: StateSlices([.contentRules])) { state in
      guard let rule = state.contentRules.first(where: { $0.id == id }) else { return }
      state.contentRules.removeAll { $0.id == id }
      state.contentRuleHits[id] = nil; state.contentRuleSkips[id] = nil
      state.invalidatePendingWork(.contentRuleRemoved(field: rule.field, pattern: rule.pattern))
    }
  }
  private struct Archive: Codable { var version = 1; var rules: [ContentRule] }
}
