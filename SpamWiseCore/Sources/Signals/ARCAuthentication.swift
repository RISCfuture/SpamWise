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
    guard let topmost = headers["authentication-results"]?.first, report(topmost).server.isEmpty,
      let seals = headers["arc-seal"], seals.count == 1,
      instance(inTags: seals[0]) == receivingInstance,
      let sets = headers["arc-authentication-results"], sets.count == 1
    else { return nil }
    let fields = sets[0].components(separatedBy: ";")
    guard let first = fields.first, instanceTag(first) == receivingInstance else { return nil }
    let server = report(fields.dropFirst().joined(separator: ";")).server
    return server.isEmpty ? nil : server
  }

  /**
   The topmost Authentication-Results header's results, trusted and attributed to the receiving
   provider's ARC authserv-id, when that authserv-id is in `trustedServers`.

   The ARC set only names the server; its own results are ignored, so a set the provider didn't
   add can neither add results to the provider's header nor leave out its failures. Empty when the
   message doesn't qualify or the authserv-id isn't trusted.
   */
  public static func resultsTrustedThroughARC(
    _ headers: [String: [String]],
    trustedServers: Set<String>
  ) -> [AuthResult] {
    guard let server = arcServer(headers), normalized(trustedServers).contains(server),
      let topmost = headers["authentication-results"]?.first
    else { return [] }
    return report(topmost).results.compactMap { result($0, server: server, trusted: true) }
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
