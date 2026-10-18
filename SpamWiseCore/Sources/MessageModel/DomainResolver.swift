import Foundation
import Darwin

/**
 Registrable-domain lookup using the bundled Mozilla Public Suffix List.

 Hosts and list rules are compared in their IDNA ASCII form, so `xn--55qx5d.cn` and `公司.cn`
 are the same public suffix, and every returned domain is lowercase ASCII.
 */
public struct DomainResolver: Sendable {
  private static let maximumLabelCharacters = 63
  private static let exceptionPrefix = "!"
  private static let wildcardPrefix = "*."
  private static let rules: Set<String> = {
    guard let url = Bundle.module.url(forResource: "public_suffix_list", withExtension: "dat"),
      let text = try? String(contentsOf: url, encoding: .utf8)
    else { preconditionFailure("The bundled Public Suffix List is missing or unreadable.") }
    return Set(
      text.components(separatedBy: .newlines).filter { !$0.isEmpty && !$0.hasPrefix("//") }
        .compactMap(asciiRule)
    )
  }()
  /// Creates a DomainResolver with the supplied configuration.
  public init() {}

  /**
   Returns a host name in lowercase IDNA ASCII form, or nil when it can't be expressed as one.

   ASCII input is only lowercased; any other input is converted with UTS #46 processing, which
   also maps full-width and uppercase characters.
   */
  public static func asciiHost(_ host: String) -> String? {
    guard !host.allSatisfy(\.isASCII) else { return host.lowercased() }
    var components = URLComponents()
    components.host = host
    guard let encoded = components.encodedHost, !encoded.contains("%") else { return nil }
    return encoded.lowercased()
  }

  /// Converts a list rule to ASCII, keeping its exception or wildcard prefix.
  private static func asciiRule(_ rule: String) -> String? {
    for prefix in [exceptionPrefix, wildcardPrefix] where rule.hasPrefix(prefix) {
      return asciiHost(String(rule.dropFirst(prefix.count))).map { prefix + $0 }
    }
    return asciiHost(rule)
  }

  /// Returns the ASCII registrable domain, or nil for IPs, public suffixes and invalid hosts.
  public func registrableDomain(_ input: String) -> String? {
    guard
      let host = Self.asciiHost(input.trimmingCharacters(in: CharacterSet(charactersIn: ".")))
    else { return nil }
    var ipv4 = in_addr(), ipv6 = in6_addr()
    guard !host.isEmpty, (unsafe inet_pton(AF_INET, host, &ipv4)) != 1,
      (unsafe inet_pton(AF_INET6, host, &ipv6)) != 1
    else { return nil }
    let labels = host.split(separator: ".").map(String.init)
    guard labels.count > 1,
      labels.allSatisfy({
        !$0.isEmpty && $0.count <= Self.maximumLabelCharacters
          && !$0.contains(where: { $0.isWhitespace || $0 == "/" || $0 == "@" })
      })
    else { return nil }
    var suffixCount = 1
    for i in labels.indices {
      let suffix = labels[i...].joined(separator: ".")
      if Self.rules.contains(Self.exceptionPrefix + suffix) {
        suffixCount = labels.count - i - 1
        break
      }
      if Self.rules.contains(suffix) { suffixCount = max(suffixCount, labels.count - i) }
      if i > 0 && Self.rules.contains(Self.wildcardPrefix + suffix) {
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
