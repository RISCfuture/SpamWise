public import Foundation

/// Failures while reserving provider spending.
public protocol BudgetFailure: Error {}

/// The user’s monthly spending limit prevented a provider request or could not be applied.
public enum SpendingLimitError: BudgetFailure, Sendable, Equatable, LocalizedError {
  /// The requested limit or reservation is not a positive amount within the supported maximum.
  case invalidAmount
  /// The request would exceed this month’s spending limit.
  case limitReached

  /// General description of the spending-limit failure.
  public var errorDescription: String? {
    switch self {
      case .invalidAmount: String(localized: "Couldn’t save the spending limit.")
      case .limitReached:
        String(
          localized: "Your monthly spending limit prevented this request. Mail was left unchanged."
        )
    }
  }
  /// The spending-limit condition that applied.
  public var failureReason: String? {
    switch self {
      case .invalidAmount:
        String(
          localized:
            "The spending limit must be a positive amount no greater than \(MonthlySpending.maximumUSD, format: .currency(code: "USD"))."
        )
      case .limitReached: String(localized: "This month’s spending limit has been reached.")
    }
  }
  /// How the user can resume paid classification.
  public var recoverySuggestion: String? {
    switch self {
      case .invalidAmount: nil
      case .limitReached:
        String(localized: "Raise the limit in Settings, or wait until next month.")
    }
  }
}

/// A Gregorian calendar month in the current time zone.
public struct BillingMonth: Codable, Hashable, Sendable {
  /// Gregorian year.
  public let year: Int
  /// Month number, 1 through 12.
  public let month: Int

  /// Creates the month that contains `date`.
  public init(containing date: Date) {
    let components = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: date)
    guard let year = components.year, let month = components.month else {
      preconditionFailure("The Gregorian calendar always supplies a year and month.")
    }
    self.year = year; self.month = month
  }
}

/// One calendar month of production provider spending and the user’s optional limit.
public struct MonthlySpending: Codable, Sendable, Equatable {
  /// Largest monthly limit, and largest single reservation, the ledger accepts in USD.
  public static let maximumUSD = 1_000_000.0
  private static let microUSDPerUSD = 1_000_000.0

  /// Optional user-set limit for each calendar month; nil leaves spending unlimited.
  public var limitMicroUSD: UInt64?
  /// Month whose spending is counted.
  public var month: BillingMonth
  /// Settled measured costs plus outstanding and possibly billed reservations this month.
  public var committedMicroUSD: UInt64 = 0
  /// Paid requests admitted this month.
  public var requests: UInt = 0
  /// Whether this month’s limit refused the most recent request it evaluated.
  public var limitReached = false

  /// The monthly limit in USD, or nil when spending is unlimited.
  public var limitUSD: Double? { limitMicroUSD.map { Double($0) / Self.microUSDPerUSD } }
  /// Spending counted toward this month’s limit, in USD.
  public var committedUSD: Double { Double(committedMicroUSD) / Self.microUSDPerUSD }

  /// Creates an unlimited ledger for `month` with nothing spent.
  public init(month: BillingMonth) { self.month = month }

  static func microUSD(_ usd: Double) throws -> UInt64 {
    guard (0...maximumUSD).contains(usd) else { throw SpendingLimitError.invalidAmount }
    return UInt64((usd * microUSDPerUSD).rounded(.toNearestOrAwayFromZero))
  }

  func current(at date: Date) -> Self {
    let month = BillingMonth(containing: date)
    guard month != self.month else { return self }
    var next = Self(month: month)
    next.limitMicroUSD = limitMicroUSD
    return next
  }
}

/// A month-scoped amount held against the spending ledger until the request settles.
public struct SpendingReservation: Sendable, Equatable {
  /// Month the reservation was counted in.
  public let month: BillingMonth
  /// Reserved amount in millionths of a US dollar.
  public let microUSD: UInt64
}

/// Cross-process monthly spending ledger for production provider requests.
public enum SpendingLimit {
  private static let key = "monthly-spending-v1"

  /// Reads the ledger for the month containing `date`.
  public static func load(_ store: Store, at date: Date = .now) async throws -> MonthlySpending {
    try await store.read(key, default: MonthlySpending(month: .init(containing: date)))
      .current(at: date)
  }
  /// Sets or removes the monthly limit without changing what has already been spent.
  public static func setLimit(usd: Double?, store: Store, at date: Date = .now) async throws {
    let limit = try usd.map(MonthlySpending.microUSD)
    guard limit != 0 else { throw SpendingLimitError.invalidAmount }
    try await store.update(key, default: MonthlySpending(month: .init(containing: date))) {
      ledger in
      ledger = ledger.current(at: date)
      ledger.limitMicroUSD = limit; ledger.limitReached = false
    }
  }
  /// Atomically counts an upper-bound estimate before a request leaves the process.
  public static func reserve(usd: Double, store: Store, at date: Date = .now) async throws
    -> SpendingReservation
  {
    let amount = try MonthlySpending.microUSD(usd)
    let reservation: SpendingReservation? = try await store.update(
      key,
      default: MonthlySpending(month: .init(containing: date))
    ) { ledger in
      ledger = ledger.current(at: date)
      if let limit = ledger.limitMicroUSD, ledger.committedMicroUSD + amount > limit {
        ledger.limitReached = true
        return nil
      }
      ledger.committedMicroUSD += amount; ledger.requests += 1; ledger.limitReached = false
      return SpendingReservation(month: ledger.month, microUSD: amount)
    }
    guard let reservation else { throw SpendingLimitError.limitReached }
    return reservation
  }
  /// Replaces a reservation with the request’s measured cost; zero refunds an unbilled request.
  public static func settle(
    _ reservation: SpendingReservation,
    costUSD: Double,
    store: Store
  ) async throws {
    let cost = try MonthlySpending.microUSD(costUSD)
    try await store.update(key, default: MonthlySpending(month: reservation.month)) { ledger in
      guard ledger.month == reservation.month else { return }
      ledger.committedMicroUSD =
        ledger.committedMicroUSD - min(reservation.microUSD, ledger.committedMicroUSD) + cost
    }
  }
}

/// Counts each paid request in the monthly spending ledger and enforces the user’s optional limit.
public struct SpendingLimitedClassifier: Classifier {
  private static let unbilledFailures: Set<ClassificationError> = [
    .missingCredential, .consentRequired, .rateLimited, .contextExceeded
  ]
  private static let settlementRetryDelay = Duration.milliseconds(50)
  private let classifier: any Classifier
  private let model: ModelIdentifier
  private let store: Store

  /// Wraps a paid classifier whose request bounds are priced with `model`’s rates.
  public init(_ classifier: any Classifier, model: ModelIdentifier, store: Store) {
    self.classifier = classifier; self.model = model; self.store = store
  }

  private static func cannotHaveBilled(_ error: any Error) -> Bool {
    if error is CancellationError || error is StoreError { return true }
    return (error as? ClassificationError).map(unbilledFailures.contains) ?? false
  }

  /**
   Reserves the request’s maximum cost, then settles it to measured usage.

   Failures that cannot have been billed are refunded: a missing credential or consent, a rate
   limit, an oversized context, a bare `CancellationError`, and a `StoreError`. Providers report
   cancellation of a dispatched request as ``ClassificationError/cancelled`` and never access
   the store, so a bare `CancellationError` or a `StoreError` means the request never left the
   process. Other failures, and settlements that still cannot be saved after one retry, keep the
   conservative reservation.
   */
  public func classify(_ input: ClassificationInput) async throws -> Verdict {
    try Task.checkCancellation()
    let estimate = try ModelTokenPricing.rates(for: model).maximumCost(of: input)
    let reservation = try await SpendingLimit.reserve(usd: estimate, store: store)
    do {
      let verdict = try await classifier.classify(input)
      let cost = verdict.usage.estimated ? estimate : verdict.usage.estimatedCost
      await settle(reservation, costUSD: cost)
      return verdict
    } catch {
      if Self.cannotHaveBilled(error) { await settle(reservation, costUSD: 0) }
      throw error
    }
  }
  private func settle(_ reservation: SpendingReservation, costUSD: Double) async {
    do {
      try await SpendingLimit.settle(reservation, costUSD: costUSD, store: store)
    } catch StoreError.lockUnavailable {
      try? await Task.sleep(for: Self.settlementRetryDelay)
      try? await SpendingLimit.settle(reservation, costUSD: costUSD, store: store)
    } catch {}
  }
}
