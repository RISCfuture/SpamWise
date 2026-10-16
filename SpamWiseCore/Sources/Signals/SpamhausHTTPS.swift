import Foundation
import MessageModel

/// Documented DBL listing codes shared by the DNS and HTTPS services.
enum SpamhausDBL {
  /// DNS zone appended to a validated domain for public-mirror queries.
  static let zone = "dbl.spamhaus.org"
  /// HTTPS response codes mapped to the equivalent DNS listing addresses.
  static let listingAddresses: [Int: String] = [
    2002: "127.0.1.2", 2004: "127.0.1.4", 2005: "127.0.1.5",
    2006: "127.0.1.6", 2102: "127.0.1.102", 2103: "127.0.1.103", 2104: "127.0.1.104",
    2105: "127.0.1.105", 2106: "127.0.1.106"
  ]
  /// DNS answers that count as a listing; every other answer remains unknown.
  static let listingAddressSet = Set(listingAddresses.values)
}

enum SpamhausHTTPS {
  private static let endpoint = URL(string: "https://apibl.spamhaus.net/lookup/v1/DBL/")!
  private static let maximumResponseBytes = 16_384
  private static let maximumCodes = 20
  private static let maximumKeyBytes = 256
  private static let keyCharacters = UInt8(ascii: "!")...UInt8(ascii: "~")
  private static let notFoundStatus = 404
  private static let listedStatus = 200

  static func request(domain: String, key: String) throws -> URLRequest {
    guard !key.isEmpty, key.utf8.count <= maximumKeyBytes,
      key.utf8.allSatisfy(keyCharacters.contains)
    else { throw URLError(.userAuthenticationRequired) }
    var request = URLRequest(url: endpoint.appending(path: domain))
    request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
    return request
  }

  static func answer(status: Int, data: Data) -> SpamhausDomainLookup.DNSAnswer {
    let unknown = SpamhausDomainLookup.DNSAnswer(status: .failed, addresses: [])
    guard data.count <= maximumResponseBytes,
      let body = try? JSONDecoder().decode(Response.self, from: data), body.status == status
    else { return unknown }
    if status == notFoundStatus, body.resp == nil { return .init(status: .notFound, addresses: []) }
    guard status == listedStatus, let values = body.resp, !values.isEmpty,
      values.count <= maximumCodes,
      values.allSatisfy({ SpamhausDBL.listingAddresses[$0] != nil })
    else { return unknown }
    return .init(
      status: .answered,
      addresses: values.compactMap { SpamhausDBL.listingAddresses[$0] }
    )
  }

  static func query(
    domain: String,
    key: String,
    timeout: Duration,
    configuration: @escaping @Sendable () -> URLSessionConfiguration = { .ephemeral }
  ) async throws -> SpamhausDomainLookup.DNSAnswer {
    let client = BoundedHTTPClient(
      policy: .init(
        maximumResponseBytes: maximumResponseBytes,
        timeout: timeout,
        acceptedStatusCodes: [listedStatus, notFoundStatus],
        mimeType: "application/json"
      ),
      configuration: configuration
    )
    let response = try await client.send(request(domain: domain, key: key))
    return answer(status: response.status, data: response.body)
  }

  private struct Response: Decodable {
    let status: Int
    let resp: [Int]?
  }
}
