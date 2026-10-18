public import Foundation
public import MessageModel

/// Message fields eligible for explicit content rules.
public enum ContentRuleField: String, Codable, Sendable, CaseIterable {
  case subject, body, listID, recipients, replyTo, contentType, attachmentNames, attachmentTypes
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
  /// Evaluation exceeded its time limit.
  case timeout
  /// General user-visible rule failure.
  public var errorDescription: String? {
    String(localized: "Content rules could not be evaluated.", bundle: .module)
  }
  /// Specific constraint preventing a decision.
  public var failureReason: String? {
    switch self {
      case .invalid:
        String(localized: "Check the rule expression and size limits.", bundle: .module)
      case .timeout:
        String(localized: "A rule exceeded the time limit and did not match.", bundle: .module)
    }
  }
}

/// Content rules that matched one message, and those that could not be evaluated.
public struct ContentRuleEvaluation: Sendable, Equatable {
  /// Matching enabled rules in winning order.
  public var matching: [ContentRule] = []
  /// Enabled rules treated as not matching because they were invalid or exceeded their time limit.
  public var skipped: [UUID: ContentRuleError] = [:]
  /**
   The first matching rule, when no skipped rule ranks ahead of it.

   `nil` when nothing matched or when a higher-precedence rule could not be evaluated,
   because that rule might have decided the message differently.
   */
  public var decisive: ContentRule?
  /// Creates an evaluation with no matching or skipped rules.
  public init() {}
}

/// Time- and input-bounded matching with explicit conflict ordering.
public enum ContentRules {
  private static let maximumRules = 100
  private static let maximumPatternCharacters = 256
  private static let maximumNoteCharacters = 500
  private static let maximumFieldUTF16Units = 200_000
  private static let windowUTF16Units = 16_000
  private static let windowOverlapUTF16Units = 1_024
  private static let ruleBudget: Duration = .milliseconds(50)
  private static let evaluationBudget: Duration = .milliseconds(250)
  private static let regularExpressionOptions: NSRegularExpression.MatchingOptions = [
    .reportProgress, .withTransparentBounds, .withoutAnchoringBounds
  ]
  /**
   Checks syntax and resource limits without evaluating any message.

   A pattern may have at most 256 characters and must fit within the overlap between matching
   windows, so a literal match is never split between two windows.
   */
  public static func validate(_ rule: ContentRule) throws(ContentRuleError) {
    guard !rule.pattern.isEmpty, rule.pattern.count <= maximumPatternCharacters,
      rule.pattern.utf16.count <= windowOverlapUTF16Units,
      rule.note.count <= maximumNoteCharacters, rule.updatedAt.timeIntervalSince1970.isFinite
    else { throw .invalid }
    if rule.operation == .regularExpression { _ = try expression(rule.pattern) }
  }
  /**
   Matches enabled rules in winning order against overlapping windows of each field.

   Matching considers only the first 200,000 UTF-16 units of a field, in overlapping
   windows of 16,000 units, so a single match never spans more than one window. An
   `equals` rule matches only fields of at most 16,000 units.

   Each rule has a 50 ms time limit within a shared 250 ms ceiling. A rule that is invalid
   or runs out of time is reported in ``ContentRuleEvaluation/skipped`` and does not match,
   so the remaining rules and later classification stages still run. Such a rule also
   prevents any lower-precedence match from becoming ``ContentRuleEvaluation/decisive``.
   */
  public static func evaluate(_ rules: [ContentRule], message: ParsedMessage)
    -> ContentRuleEvaluation
  {
    let ceiling = ContinuousClock.now.advanced(by: evaluationBudget)
    var evaluation = ContentRuleEvaluation()
    for (index, rule) in winningOrder(rules).enumerated() {
      do throws(ContentRuleError) {
        guard index < maximumRules else { throw ContentRuleError.invalid }
        let deadline = min(ceiling, ContinuousClock.now.advanced(by: ruleBudget))
        if try matches(rule, text: value(rule.field, message: message), deadline: deadline) {
          if evaluation.matching.isEmpty, evaluation.skipped.isEmpty { evaluation.decisive = rule }
          evaluation.matching.append(rule)
        }
      } catch {
        evaluation.skipped[rule.id] = error
      }
    }
    return evaluation
  }
  private static func winningOrder(_ rules: [ContentRule]) -> [ContentRule] {
    rules.filter(\.enabled).sorted {
      $0.updatedAt == $1.updatedAt
        ? $0.id.uuidString < $1.id.uuidString : $0.updatedAt > $1.updatedAt
    }
  }
  private static func value(_ field: ContentRuleField, message: ParsedMessage) -> String {
    switch field {
      case .subject: message.subject
      case .body: message.text
      case .listID: message.decodedHeaders("list-id").first ?? ""
      case .recipients:
        (message.decodedHeaders("to") + message.decodedHeaders("cc")).joined(separator: "\n")
      case .replyTo: message.decodedHeaders("reply-to").first ?? ""
      case .contentType: message.decodedHeaders("content-type").first ?? ""
      case .attachmentNames:
        (message.attachments ?? []).compactMap(\.filename).joined(separator: "\n")
      case .attachmentTypes: (message.attachments ?? []).map(\.mediaType).joined(separator: "\n")
    }
  }
  private static func matches(
    _ rule: ContentRule,
    text: String,
    deadline: ContinuousClock.Instant
  ) throws(ContentRuleError) -> Bool {
    try validate(rule)
    let field = NSString(string: text)
    switch rule.operation {
      case .contains:
        return try anyWindow(of: field, deadline: deadline) { window in
          field.range(of: rule.pattern, options: .caseInsensitive, range: window).location
            != NSNotFound
        }
      case .equals:
        return field.length <= windowUTF16Units
          && field.compare(rule.pattern, options: .caseInsensitive) == .orderedSame
      case .regularExpression:
        let expression = try expression(rule.pattern)
        return try anyWindow(of: field, deadline: deadline) { window throws(ContentRuleError) in
          try regex(expression, field: field, window: window, deadline: deadline)
        }
    }
  }
  private static func anyWindow(
    of field: NSString,
    deadline: ContinuousClock.Instant,
    _ matches: (NSRange) throws(ContentRuleError) -> Bool
  ) throws(ContentRuleError) -> Bool {
    for window in windows(of: field) {
      try checkDeadline(deadline)
      if try matches(window) { return true }
    }
    return false
  }
  /// Overlapping UTF-16 ranges that cover the field's bounded prefix.
  private static func windows(of field: NSString) -> [NSRange] {
    let length = min(field.length, maximumFieldUTF16Units)
    guard length > windowUTF16Units else { return [NSRange(location: 0, length: length)] }
    return stride(
      from: 0,
      to: length - windowOverlapUTF16Units,
      by: windowUTF16Units - windowOverlapUTF16Units
    ).map { NSRange(location: $0, length: min(windowUTF16Units, length - $0)) }
  }
  private static func expression(_ pattern: String) throws(ContentRuleError)
    -> NSRegularExpression
  {
    do { return try NSRegularExpression(pattern: pattern, options: .caseInsensitive) } catch {
      throw .invalid
    }
  }
  private static func checkDeadline(_ deadline: ContinuousClock.Instant) throws(ContentRuleError) {
    guard ContinuousClock.now < deadline else { throw .timeout }
  }
  private static func regex(
    _ expression: NSRegularExpression,
    field: NSString,
    window: NSRange,
    deadline: ContinuousClock.Instant
  ) throws(ContentRuleError) -> Bool {
    var found = false
    unsafe expression.enumerateMatches(
      in: field as String,
      options: regularExpressionOptions,
      range: window
    ) {
      match,
      _,
      stop in
      if ContinuousClock.now >= deadline || match != nil {
        found = match != nil
        unsafe stop.pointee = true
      }
    }
    if !found { try checkDeadline(deadline) }
    return found
  }
}
