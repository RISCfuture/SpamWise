public import Foundation
import MessageModel

extension SenderRule {
  /// Decodes a stored rule, holding a domain rule in the IDNA ASCII form sender domains are matched in.
  public init(from decoder: any Decoder) throws {
    let stored = try Stored(from: decoder)
    self.init(
      scope: stored.scope,
      value: stored.scope == .domain
        ? DomainResolver.asciiHost(stored.value) ?? stored.value : stored.value,
      disposition: stored.disposition,
      updatedAt: stored.updatedAt
    )
  }

  private struct Stored: Decodable {
    var scope: RuleScope
    var value: String
    var disposition: RuleDisposition
    var updatedAt: Date
  }
}
