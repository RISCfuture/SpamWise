import Foundation
import Darwin

/// Registrable-domain lookup using the bundled Mozilla Public Suffix List.
public struct DomainResolver: Sendable {
  private static let maximumLabelCharacters = 63
  private static let rules: Set<String> = {
    guard let url = Bundle.module.url(forResource: "public_suffix_list", withExtension: "dat"),
      let text = try? String(contentsOf: url, encoding: .utf8)
    else { return [] }
    return Set(
      text.components(separatedBy: .newlines).filter { !$0.isEmpty && !$0.hasPrefix("//") }
    )
  }()
  /// Creates a DomainResolver with the supplied configuration.
  public init() {}
  /// Returns the registrable domain or nil for IPs and public suffixes.
  public func registrableDomain(_ input: String) -> String? {
    let host = input.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    var ipv4 = in_addr(), ipv6 = in6_addr()
    guard !host.isEmpty, (unsafe inet_pton(AF_INET, host, &ipv4)) != 1,
      (unsafe inet_pton(AF_INET6, host, &ipv6)) != 1
    else { return nil }
    let labels = host.split(separator: ".").map(String.init)
    guard labels.count > 1,
      labels.allSatisfy({
        !$0.isEmpty && $0.count <= Self.maximumLabelCharacters
          && !$0.contains(where: { $0.isWhitespace || $0 == "/" || $0 == "@" })
      }), !Self.rules.isEmpty
    else { return nil }
    var suffixCount = 1
    for i in labels.indices {
      let suffix = labels[i...].joined(separator: ".")
      if Self.rules.contains("!" + suffix) { suffixCount = labels.count - i - 1; break }
      if Self.rules.contains(suffix) { suffixCount = max(suffixCount, labels.count - i) }
      if i > 0 && Self.rules.contains("*." + suffix) {
        suffixCount = max(suffixCount, labels.count - i + 1)
      }
    }
    guard labels.count > suffixCount else { return nil }
    return labels.suffix(suffixCount + 1).joined(separator: ".")
  }
  /// Resolves a sender address to its registrable domain.
  public func domain(ofAddress address: String) -> String? {
    guard let host = address.split(separator: "@").last, address.contains("@") else { return nil }
    return registrableDomain(String(host))
  }
}
