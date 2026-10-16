public import Foundation
public import MessageModel

/// Message fields eligible for explicit content rules.
public enum ContentRuleField: String, Codable, Sendable, CaseIterable {
  case subject, body, listID, recipients, replyTo, contentType
}
/// Supported bounded match operators.
public enum ContentRuleOperator: String, Codable, Sendable, CaseIterable {
  case contains, equals, regularExpression
}
/// A user-authored rule evaluated after sender rules and before relationship trust.
public struct ContentRule: Codable, Sendable, Identifiable, Equatable {
  /// Stable rule identity across edits.
  public var id = UUID()
  /// Selected message field.
  public var field: ContentRuleField = .subject
  /// Selected comparison operator.
  public var operation: ContentRuleOperator = .contains
  /// Bounded expression, treated as configuration rather than instructions.
  public var pattern = ""
  /// Explicit allow or block disposition.
  public var disposition: RuleDisposition = .block
  /// Whether the rule participates in classification.
  public var enabled = true
  /// User's explanation of this rule.
  public var note = ""
  /// Latest edit; newer matching content rules take precedence.
  public var updatedAt = Date()
  /// Creates an empty rule for staged editing and validation.
  public init() {}
}

/// Invalid or over-budget explicit content rules.
public protocol ContentRuleFailure: Error {}

/// Syntax and deadline failures that prevent safe rule evaluation.
public enum ContentRuleError: ContentRuleFailure, LocalizedError, Sendable {
  /// Invalid syntax or unsupported configuration bounds.
  case invalid
  /// Evaluation exceeded its deadline and cannot safely determine precedence.
  case timeout
  /// General user-visible rule failure.
  public var errorDescription: String? {
    String(localized: "Content rules could not be evaluated.")
  }
  /// Specific constraint preventing a decision.
  public var failureReason: String? {
    switch self {
      case .invalid: String(localized: "Check the rule expression and size limits.")
      case .timeout: String(localized: "A rule exceeded the time limit. Mail remains unchanged.")
    }
  }
}

/// Time- and input-bounded matching with explicit conflict ordering.
public enum ContentRules {
  private static let maximumRules = 100
  private static let maximumPatternCharacters = 256
  private static let maximumNoteCharacters = 500
  private static let maximumInputCharacters = 16_000
  private static let evaluationBudget: Duration = .milliseconds(100)
  /// Checks syntax and resource limits without evaluating any message.
  public static func validate(_ rule: ContentRule) throws {
    guard !rule.pattern.isEmpty, rule.pattern.count <= maximumPatternCharacters,
      rule.note.count <= maximumNoteCharacters
    else { throw ContentRuleError.invalid }
    if rule.operation == .regularExpression {
      do { _ = try NSRegularExpression(pattern: rule.pattern, options: .caseInsensitive) } catch {
        throw ContentRuleError.invalid
      }
    }
  }
  /// Returns all matches in winning order for previews; throws instead of ignoring a timed-out rule.
  public static func matches(_ rules: [ContentRule], message: ParsedMessage) throws -> [ContentRule]
  {
    guard rules.count <= maximumRules else { throw ContentRuleError.invalid }
    let deadline = ContinuousClock.now.advanced(by: evaluationBudget)
    var matching: [ContentRule] = []
    for rule in rules.filter(\.enabled).sorted(by: {
      $0.updatedAt == $1.updatedAt
        ? $0.id.uuidString < $1.id.uuidString : $0.updatedAt > $1.updatedAt
    }) {
      try validate(rule)
      guard ContinuousClock.now < deadline else { throw ContentRuleError.timeout }
      let text = String(value(rule.field, message: message).prefix(maximumInputCharacters))
      let match: Bool
      switch rule.operation {
        case .contains: match = text.range(of: rule.pattern, options: .caseInsensitive) != nil
        case .equals: match = text.compare(rule.pattern, options: .caseInsensitive) == .orderedSame
        case .regularExpression: match = try regex(rule.pattern, text: text, deadline: deadline)
      }
      if match { matching.append(rule) }
    }
    return matching
  }
  private static func value(_ field: ContentRuleField, message: ParsedMessage) -> String {
    switch field {
      case .subject: message.subject
      case .body: message.text
      case .listID: message.header("list-id") ?? ""
      case .recipients:
        ((message.headers["to"] ?? []) + (message.headers["cc"] ?? [])).joined(separator: "\n")
      case .replyTo: message.header("reply-to") ?? ""
      case .contentType: message.header("content-type") ?? ""
    }
  }
  private static func regex(_ pattern: String, text: String, deadline: ContinuousClock.Instant)
    throws -> Bool
  {
    let expression = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
    var found = false, expired = false
    unsafe expression.enumerateMatches(
      in: text,
      options: [.reportProgress],
      range: NSRange(text.startIndex..., in: text)
    ) {
      match,
      _,
      stop in
      if ContinuousClock.now >= deadline {
        expired = true
        unsafe stop.pointee = true
      } else if match != nil {
        found = true
        unsafe stop.pointee = true
      }
    }
    guard !expired, ContinuousClock.now < deadline else { throw ContentRuleError.timeout }
    return found
  }
}
