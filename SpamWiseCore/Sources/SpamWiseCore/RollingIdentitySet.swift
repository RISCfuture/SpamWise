/**
 A set of identities that forgets the oldest member once it holds `capacity` members.

 History import uses it to avoid counting a message twice. Forgetting an identity can only cause
 a message that was already counted to be counted again, which raises a count that is already
 positive; relationship gates test only whether a count is positive, so eviction never changes
 a gate decision.
 */
public struct RollingIdentitySet: Codable, Sendable, Equatable {
  /// Maximum number of remembered identities.
  public let capacity: Int
  private var order: [String] = []
  private var members: Set<String> = []
  /// Number of remembered identities.
  public var count: Int { order.count }
  /// Creates a set holding at most `capacity` of the latest `identities`.
  public init(capacity: Int, _ identities: [String] = []) {
    self.capacity = max(1, capacity)
    for identity in identities { insert(identity) }
  }
  /// Decodes an ordered identity list, oldest first.
  public init(from decoder: any Decoder) throws {
    self.init(
      capacity: RetentionLimits.historyImportIdentities,
      try decoder.singleValueContainer().decode([String].self)
    )
  }
  /// Encodes the identities oldest first.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(order)
  }
  /// Whether `identity` is remembered.
  public func contains(_ identity: String) -> Bool { members.contains(identity) }
  /// Remembers `identity`, forgetting the oldest member when full.
  @discardableResult public mutating func insert(_ identity: String) -> (
    inserted: Bool, memberAfterInsert: String
  ) {
    guard members.insert(identity).inserted else { return (false, identity) }
    order.append(identity)
    if order.count > capacity { members.remove(order.removeFirst()) }
    return (true, identity)
  }
}
