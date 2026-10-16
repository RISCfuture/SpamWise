public import Foundation

/// Failures while configuring or reserving provider spending.
public protocol BudgetFailure: Error {}

/// A spending ceiling or invalid budget request prevented a provider call.
public enum BudgetError: BudgetFailure, Sendable, LocalizedError {
  /// The requested ceiling or reservation is not a valid amount.
  case invalidAmount
  /// The reservation would exceed the authorized ceiling.
  case exhausted
  /// User-visible reason that classification was not attempted.
  public var errorDescription: String? {
    String(localized: "Evaluation spending is unavailable. No provider call was made.")
  }
  /// The budget constraint that prevented the operation.
  public var failureReason: String? {
    switch self {
      case .invalidAmount: String(localized: "The requested spending amount is invalid.")
      case .exhausted: String(localized: "The evaluation spending limit has been reached.")
    }
  }
}
/// Conservative lifetime spending commitments, separate from measured token-cost estimates.
public struct BudgetLedger: Codable, Sendable {
  /// Maximum additional evaluation spending authorized in USD.
  public var limitUSD: Double = 150
  /// Sum of upper bounds reserved before calls, including calls whose billing outcome is unknown.
  public var committedUSD: Double = 0
  /// Number of provider requests admitted by the ledger.
  public var calls: Int = 0
  /// Creates an empty $150 authorization ledger.
  public init() {}
}
/// Cross-process conservative reservations that never refund an uncertain provider request.
public enum EvaluationBudget {
  private static let key = "evaluation-budget-v1"
  /// Reads the authorization ledger without issuing network requests.
  public static func load(_ store: Store) async throws -> BudgetLedger {
    try await store.read(key, default: BudgetLedger())
  }
  /// Changes the ceiling without resetting prior commitments.
  public static func configure(limitUSD: Double, store: Store) async throws {
    guard limitUSD.isFinite, limitUSD >= 0 else { throw BudgetError.invalidAmount }
    try await store.update(key, default: BudgetLedger()) { ledger in ledger.limitUSD = limitUSD }
  }
  /// Atomically reserves a conservative per-call upper bound before any request leaves the process.
  public static func reserve(upperBoundUSD: Double, store: Store) async throws {
    guard upperBoundUSD.isFinite, upperBoundUSD > 0 else { throw BudgetError.invalidAmount }
    try await store.update(key, default: BudgetLedger()) { ledger in
      guard ledger.committedUSD + upperBoundUSD <= ledger.limitUSD else {
        throw BudgetError.exhausted
      }
      ledger.committedUSD += upperBoundUSD; ledger.calls += 1
    }
  }
}

/// Reserves spending before invoking an explicitly configured paid classifier.
public struct BudgetedClassifier: Classifier {
  private let classifier: any Classifier
  private let store: Store
  private let upperBoundUSD: Double
  /// Creates a wrapper with a caller-supplied bound for the configured model and prompt limits.
  public init(_ classifier: any Classifier, store: Store, upperBoundUSD: Double) {
    self.classifier = classifier; self.store = store; self.upperBoundUSD = upperBoundUSD
  }
  /// Consumes a reservation even when a request fails, since its billing outcome may be unknown.
  public func classify(_ input: ClassificationInput) async throws -> Verdict {
    try Task.checkCancellation()
    try await EvaluationBudget.reserve(upperBoundUSD: upperBoundUSD, store: store)
    return try await classifier.classify(input)
  }
}
