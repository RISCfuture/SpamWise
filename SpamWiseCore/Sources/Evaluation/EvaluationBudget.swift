public import Foundation
public import SpamWiseCore

/// An evaluation spending ceiling or invalid budget request prevented a provider call.
public enum BudgetError: BudgetFailure, Sendable, LocalizedError {
  /// A paid model was selected without an explicit evaluation ledger.
  case missingStore
  /// The requested ceiling or reservation is not a valid amount.
  case invalidAmount
  /// The selected ledger has no explicitly configured ceiling.
  case unconfigured
  /// The reservation would exceed the authorized ceiling.
  case exhausted
  /// User-visible reason that classification was not attempted.
  public var errorDescription: String? {
    String(
      localized: "Evaluation spending is unavailable. No provider call was made.",
      bundle: .module
    )
  }
  /// The budget constraint that prevented the operation.
  public var failureReason: String? {
    switch self {
      case .missingStore:
        String(localized: "Paid models require --budget-store PATH.", bundle: .module)
      case .invalidAmount:
        String(localized: "The requested spending amount is invalid.", bundle: .module)
      case .unconfigured:
        String(
          localized: "The budget store has no ceiling. Set one with --budget-limit USD.",
          bundle: .module
        )
      case .exhausted:
        String(localized: "The evaluation spending limit has been reached.", bundle: .module)
    }
  }
}
/// Conservative lifetime spending commitments, separate from measured token-cost estimates.
public struct BudgetLedger: Codable, Sendable {
  /// Maximum evaluation spending authorized in USD.
  public var limitUSD: Double
  /// Sum of upper bounds reserved before calls, including calls whose billing outcome is unknown.
  public var committedUSD: Double = 0
  /// Number of provider requests admitted by the ledger.
  public var calls: Int = 0
  /// Creates an empty ledger with an explicit ceiling.
  public init(limitUSD: Double) { self.limitUSD = limitUSD }
}
/// Cross-process conservative reservations that never refund an uncertain provider request.
public enum EvaluationBudget {
  private static let key = "evaluation-budget-v1"
  /// Reads the authorization ledger, or nil when no ceiling has been configured.
  public static func load(_ store: Store) async throws -> BudgetLedger? {
    try await store.read(key, default: BudgetLedger?.none)
  }
  /**
   Opens the explicit ledger that paid evaluation requires, never defaulting to the app’s store.

   A supplied `limitUSD` becomes the ledger’s ceiling; without one, the ledger must already
   have a ceiling.
   */
  public static func ledgerStore(at url: URL?, limitUSD: Double?) async throws -> Store {
    guard let url else { throw BudgetError.missingStore }
    let store = try Store(url: url)
    if let limitUSD { try await configure(limitUSD: limitUSD, store: store) }
    guard try await load(store) != nil else { throw BudgetError.unconfigured }
    return store
  }
  /// Sets the ceiling, creating the ledger if needed, without resetting prior commitments.
  public static func configure(limitUSD: Double, store: Store) async throws {
    guard limitUSD.isFinite, limitUSD >= 0 else { throw BudgetError.invalidAmount }
    try await store.update(key, default: BudgetLedger(limitUSD: limitUSD)) { ledger in
      ledger.limitUSD = limitUSD
    }
  }
  /// Atomically reserves a conservative per-call upper bound before any request leaves the process.
  public static func reserve(upperBoundUSD: Double, store: Store) async throws {
    guard upperBoundUSD.isFinite, upperBoundUSD > 0 else { throw BudgetError.invalidAmount }
    try await store.update(key, default: BudgetLedger?.none) { ledger in
      guard var current = ledger else { throw BudgetError.unconfigured }
      guard current.committedUSD + upperBoundUSD <= current.limitUSD else {
        throw BudgetError.exhausted
      }
      current.committedUSD += upperBoundUSD; current.calls += 1
      ledger = current
    }
  }
}

/// Reserves evaluation spending before invoking an explicitly configured paid classifier.
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
