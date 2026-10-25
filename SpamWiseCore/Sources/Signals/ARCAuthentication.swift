import Foundation

/**
 ARC-Authentication-Results as a receiving-server trust source, for providers such as Microsoft
 365 and Outlook.com whose Authentication-Results headers carry no authserv-id.

 ARC signatures are not verified, so trust comes from position alone. A message qualifies only when
 its topmost Authentication-Results header has no authserv-id and its ARC chain is a single set of
 instance 1: the provider adds that set on receipt, and any set a sender supplied would make the
 provider's own set a later instance.
 */
extension AuthenticationHeaders {
  private static let receivingInstance = 1

  /// The authserv-id of the receiving provider's ARC set, or nil when the message doesn't qualify.
  public static func arcServer(_ headers: [String: [String]]) -> String? {
    receivingARCReport(headers)?.server
  }

  /**
   The receiving provider's ARC results, trusted, when its authserv-id is in `trustedServers`.

   Only results that the topmost Authentication-Results header also reports, with the same
   mechanism, result and domain, are returned, so an ARC set that the provider didn't add can't
   claim more than the provider's own header. Empty when the message doesn't qualify or the
   authserv-id isn't trusted.
   */
  public static func trustedARCResults(
    _ headers: [String: [String]],
    trustedServers: Set<String>
  ) -> [AuthResult] {
    guard let arc = receivingARCReport(headers), normalized(trustedServers).contains(arc.server),
      let topmost = headers["authentication-results"]?.first
    else { return [] }
    let corroborating = report(topmost).results.compactMap {
      result($0, server: arc.server, trusted: true)
    }
    return arc.results.compactMap { result($0, server: arc.server, trusted: true) }
      .filter(corroborating.contains)
  }

  private static func receivingARCReport(_ headers: [String: [String]])
    -> (server: String, results: ArraySlice<String>)?
  {
    guard let topmost = headers["authentication-results"]?.first, report(topmost).server.isEmpty,
      let seals = headers["arc-seal"], seals.count == 1,
      instance(inTags: seals[0]) == receivingInstance,
      let sets = headers["arc-authentication-results"], sets.count == 1
    else { return nil }
    let fields = sets[0].components(separatedBy: ";")
    guard let first = fields.first, instanceTag(first) == receivingInstance else { return nil }
    let payload = report(fields.dropFirst().joined(separator: ";"))
    return payload.server.isEmpty ? nil : payload
  }

  /// The `i=` value among a header's `;`-separated tags.
  private static func instance(inTags header: String) -> Int? {
    header.components(separatedBy: ";").lazy.compactMap(instanceTag).first
  }

  /// The value of one tag when it is `i=`.
  private static func instanceTag(_ tag: String) -> Int? {
    let parts = tag.split(separator: "=", maxSplits: 1)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    guard parts.count == 2, parts[0].lowercased() == "i" else { return nil }
    return Int(parts[1])
  }
}
