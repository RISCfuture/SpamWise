public import Foundation

/// Which elements of a keyed collection a transaction reads.
public enum StateSelection<Key: Hashable & Sendable>: Sendable {
  /// Reads no existing elements; added elements are still written.
  case none
  /// Reads only the elements with these keys.
  case only(Set<Key>)
  /// Reads the whole collection.
  case all
}

/**
 The parts of ``AppState`` a transaction reads.

 Settings, the policy revision and usage totals are always read. Every other part starts
 empty unless selected. A transaction may add or replace elements of any collection, but it
 deletes only elements it read, and it may change a document only after reading it.
 ``AppState/invalidatePendingWork(_:)`` discards all retries and the undo snapshot
 whether or not they were read.
 */
public struct StateSlices: Sendable {
  /// Everything in the store, including the whole Activity log.
  public static let everything = StateSlices(
    .all,
    records: .all,
    retries: .all,
    claims: .all,
    histories: .all,
    reviewedLabels: .all
  )
  /// Selected whole parts.
  public var parts: Parts
  /// Selected Activity records.
  public var records: StateSelection<UUID>
  /// Selected retries, keyed by message identity key.
  public var retries: StateSelection<String>
  /// Selected action claims, keyed by message identity key.
  public var claims: StateSelection<String>
  /// Selected histories, keyed by account identifier.
  public var histories: StateSelection<String>
  /// Selected reviewed labels, keyed by content identity.
  public var reviewedLabels: StateSelection<String>
  /// Creates a selection; omitted collections read nothing.
  public init(
    _ parts: Parts = [],
    records: StateSelection<UUID> = .none,
    retries: StateSelection<String> = .none,
    claims: StateSelection<String> = .none,
    histories: StateSelection<String> = .none,
    reviewedLabels: StateSelection<String> = .none
  ) {
    self.parts = parts; self.records = records; self.retries = retries; self.claims = claims
    self.histories = histories; self.reviewedLabels = reviewedLabels
  }
  /// Whole collections and documents a transaction can read.
  public struct Parts: OptionSet, Sendable {
    /// Explicit sender rules.
    public static let rules = Parts(rawValue: 1 << 0)
    /// Content rules and their winning-match and skip counts.
    public static let contentRules = Parts(rawValue: 1 << 1)
    /// Quoted correction examples.
    public static let corrections = Parts(rawValue: 1 << 2)
    /// Derived learning state.
    public static let learning = Parts(rawValue: 1 << 3)
    /// The correction undo snapshot.
    public static let undo = Parts(rawValue: 1 << 4)
    /// Cached Contacts and own addresses.
    public static let contacts = Parts(rawValue: 1 << 5)
    /// Training-folder claims and observations.
    public static let training = Parts(rawValue: 1 << 6)
    /// Existing audit events, needed only to display them.
    public static let audit = Parts(rawValue: 1 << 7)
    /// History import identities, needed only to import more history.
    public static let historyImports = Parts(rawValue: 1 << 8)
    /// Receiving-server identifiers observed in each account's mail.
    public static let authentication = Parts(rawValue: 1 << 9)
    /// Every part.
    public static let all: Parts = [
      .rules, .contentRules, .corrections, .learning, .undo, .contacts, .training, .audit,
      .historyImports, .authentication
    ]
    /// Bit mask of selected parts.
    public let rawValue: Int
    /// Creates parts from a bit mask.
    public init(rawValue: Int) { self.rawValue = rawValue }
  }
}

/// Names of independently changing state slices, used as change-token keys.
public enum StateSlice: String, Sendable, CaseIterable {
  case policy, meta, contacts, training, learning, undo, rules, contentRules, contentRuleHits
  case contentRuleSkips, corrections, reviewedLabels, audit, records, retries, claims, histories,
    mailHealth, authentication
}
