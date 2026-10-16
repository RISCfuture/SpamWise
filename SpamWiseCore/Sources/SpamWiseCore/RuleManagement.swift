public import Foundation

/// Invalid, oversized or unsupported sender-rule imports.
public enum RuleManagementError: Error, Sendable, LocalizedError {
  case invalidRule, invalidArchive, tooManyRules
  /// A user-visible explanation of the rejected rule operation.
  public var errorDescription: String? {
    switch self {
      case .invalidRule:
        String(localized: "Enter a complete email address or a registrable domain.")
      case .invalidArchive:
        String(localized: "The rule file is invalid or exceeds the import limit.")
      case .tooManyRules: String(localized: "The maximum of 10,000 sender rules has been reached.")
    }
  }
}

/// Atomic editing and portable JSON import/export of explicit sender rules.
public enum RuleManagement {
  private struct Archive: Codable { var version = 1; var rules: [SenderRule] }
  /// Validates a literal email address or registrable domain without broadening its scope.
  public static func normalized(_ value: String, scope: RuleScope) throws -> String {
    let value = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !value.isEmpty, value.utf8.count <= 254 else { throw RuleManagementError.invalidRule }
    switch scope {
      case .address:
        guard MIMEParser.address(value) == value, !value.contains("<"), !value.contains(">") else {
          throw RuleManagementError.invalidRule
        }
      case .domain:
        guard DomainResolver().registrableDomain(value) == value, !value.contains("@") else {
          throw RuleManagementError.invalidRule
        }
    }
    return value
  }
  /// Saves the latest explicit rule at its chosen scope and invalidates pending classifications.
  public static func save(
    scope: RuleScope,
    value: String,
    disposition: RuleDisposition,
    store: Store
  ) async throws {
    let rule = SenderRule(
      scope: scope,
      value: try normalized(value, scope: scope),
      disposition: disposition
    )
    try await StateRepository.update(store) { state in
      state.rules = Gates.replacing(rule, in: state.rules)
      guard state.rules.count <= 10_000 else { throw RuleManagementError.tooManyRules }
      state.revision += 1; state.retries.removeAll()
    }
  }
  /// Removes only the selected scoped rule; existing mail actions are not reversed.
  public static func remove(id: String, store: Store) async throws {
    try await StateRepository.update(store) { state in
      state.rules.removeAll { $0.id == id }
      state.revision += 1; state.retries.removeAll()
    }
  }
  /// Serializes rules without mail bodies, API keys or correction examples.
  public static func exportRules(_ rules: [SenderRule]) throws -> Data {
    guard rules.count <= 10_000 else { throw RuleManagementError.tooManyRules }
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(Archive(rules: rules.sorted { $0.id < $1.id }))
  }
  /// Validates the whole archive before merging; imported rules replace matching scopes atomically.
  public static func importRules(_ data: Data, store: Store) async throws {
    guard data.count <= 2_000_000 else { throw RuleManagementError.invalidArchive }
    let archive: Archive
    do { archive = try JSONDecoder().decode(Archive.self, from: data) } catch {
      throw RuleManagementError.invalidArchive
    }
    guard archive.version == 1, archive.rules.count <= 10_000 else {
      throw RuleManagementError.invalidArchive
    }
    let rules = try archive.rules.map {
      SenderRule(
        scope: $0.scope,
        value: try normalized($0.value, scope: $0.scope),
        disposition: $0.disposition
      )
    }
    try await StateRepository.update(store) { state in
      for rule in rules { state.rules = Gates.replacing(rule, in: state.rules) }
      guard state.rules.count <= 10_000 else { throw RuleManagementError.tooManyRules }
      state.revision += 1; state.retries.removeAll()
    }
  }
}
