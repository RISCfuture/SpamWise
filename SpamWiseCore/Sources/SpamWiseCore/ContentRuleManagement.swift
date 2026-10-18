public import Foundation

/// Atomic editing of bounded content rules; sender rules always retain precedence.
public enum ContentRuleManagement {
  private static let maximumRules = 100
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
    try await StateRepository.update(store) { state in
      let importedIDs = Set(archive.rules.map(\.id))
      let combined =
        (state.contentRules ?? []).filter { !importedIDs.contains($0.id) } + archive.rules
      try validate(combined)
      state.contentRules = combined
      for id in importedIDs { state.contentRuleSkips?[id] = nil }
      state.revision += 1; state.retries.removeAll()
      state.audit(
        .contentRule,
        detail: String(localized: "Imported \(archive.rules.count) content rules")
      )
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
    try await StateRepository.update(store) { state in
      var rules = state.contentRules ?? []
      rules.removeAll { $0.id == saved.id }
      rules.append(saved)
      guard rules.count <= maximumRules else { throw ContentRuleError.invalid }
      state.contentRules = rules
      state.contentRuleSkips?[saved.id] = nil
      state.revision += 1; state.retries.removeAll()
      state.audit(
        .contentRule,
        detail: String(localized: "Saved \(saved.id.uuidString): \(saved.disposition.rawValue)")
      )
    }
  }
  /// Removes one rule without modifying mail or other rules.
  public static func remove(_ id: UUID, store: Store) async throws {
    try await StateRepository.update(store) {
      $0.contentRules?.removeAll { $0.id == id }
      $0.contentRuleSkips?[id] = nil
      $0.revision += 1; $0.retries.removeAll()
      $0.audit(.contentRule, detail: String(localized: "Removed \(id.uuidString)"))
    }
  }
  private struct Archive: Codable { var version = 1; var rules: [ContentRule] }
}
