public import Foundation

/// Failures while validating, editing, or importing sender rules.
public protocol RuleManagementFailure: Error {}

/// Invalid, oversized or unsupported sender-rule imports.
public enum RuleManagementError: RuleManagementFailure, Sendable, LocalizedError {
  /// A value is not a complete address or registrable domain at its selected scope.
  case invalidRule
  /// An archive has an invalid schema, encoding, or size.
  case invalidArchive
  /// The rule operation would exceed the supported rule count.
  case tooManyRules
  /// A user-visible explanation of the rejected rule operation.
  public var errorDescription: String? {
    String(localized: "The sender rules could not be updated.")
  }
  /// The validation constraint that rejected the operation.
  public var failureReason: String? {
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
  private static let maximumRuleBytes = 254
  private static let maximumRules = RetentionLimits.senderRules
  private static let maximumArchiveBytes = 2_000_000
  /**
   Validates a literal email address or registrable domain without broadening its scope.

   A domain is returned in its IDNA ASCII form, the form sender domains are matched in.
   */
  public static func normalized(_ value: String, scope: RuleScope) throws -> String {
    let value = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !value.isEmpty, value.utf8.count <= maximumRuleBytes else {
      throw RuleManagementError.invalidRule
    }
    switch scope {
      case .address:
        guard MIMEParser.address(value) == value, !value.contains("<"), !value.contains(">") else {
          throw RuleManagementError.invalidRule
        }
        return value
      case .domain:
        guard let domain = DomainResolver.asciiHost(value), !value.contains("@"),
          DomainResolver().registrableDomain(domain) == domain
        else { throw RuleManagementError.invalidRule }
        return domain
    }
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
    try await StateRepository.update(store, loading: StateSlices([.rules])) { state in
      state.rules = Gates.replacing(rule, in: state.rules)
      guard state.rules.count <= maximumRules else { throw RuleManagementError.tooManyRules }
      state.invalidatePendingWork(
        .senderRuleSaved(scope: rule.scope, value: rule.value, disposition: rule.disposition)
      )
    }
  }
  /// Removes only the selected scoped rule; existing mail actions are not reversed.
  public static func remove(id: String, store: Store) async throws {
    try await StateRepository.update(store, loading: StateSlices([.rules])) { state in
      guard let rule = state.rules.first(where: { $0.id == id }) else { return }
      state.rules.removeAll { $0.id == id }
      state.invalidatePendingWork(.senderRuleRemoved(scope: rule.scope, value: rule.value))
    }
  }
  /// Serializes rules without mail bodies, API keys or correction examples.
  public static func exportRules(_ rules: [SenderRule]) throws -> Data {
    guard rules.count <= maximumRules else { throw RuleManagementError.tooManyRules }
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(Archive(rules: rules.sorted { $0.id < $1.id }))
  }
  /// Validates the whole archive before merging; imported rules replace matching scopes atomically.
  public static func importRules(_ data: Data, store: Store) async throws {
    guard data.count <= maximumArchiveBytes else { throw RuleManagementError.invalidArchive }
    let archive: Archive
    do { archive = try JSONDecoder().decode(Archive.self, from: data) } catch {
      throw RuleManagementError.invalidArchive
    }
    guard archive.version == 1, archive.rules.count <= maximumRules else {
      throw RuleManagementError.invalidArchive
    }
    let rules = try archive.rules.map {
      SenderRule(
        scope: $0.scope,
        value: try normalized($0.value, scope: $0.scope),
        disposition: $0.disposition
      )
    }
    try await StateRepository.update(store, loading: StateSlices([.rules])) { state in
      for rule in rules { state.rules = Gates.replacing(rule, in: state.rules) }
      guard state.rules.count <= maximumRules else { throw RuleManagementError.tooManyRules }
      state.invalidatePendingWork(.senderRulesImported(count: rules.count))
    }
  }
  private struct Archive: Codable { var version = 1; var rules: [SenderRule] }
}

extension AppState {
  /// Counts the distinct senders seen in Activity or corrections at each registrable domain.
  public func knownSenderCounts(atDomains domains: Set<String>) -> [String: Int] {
    let domains = Set(domains.map { $0.lowercased() })
    guard !domains.isEmpty else { return [:] }
    let resolver = DomainResolver()
    let senders = Set(
      (records.compactMap(\.sender) + corrections.map(\.sender)).map { $0.lowercased() }
    )
    var counts: [String: Int] = [:]
    for sender in senders {
      guard let domain = resolver.domain(ofAddress: sender), domains.contains(domain) else {
        continue
      }
      counts[domain, default: 0] += 1
    }
    return counts
  }
}
