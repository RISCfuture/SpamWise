public import Foundation
import MessageModel

/// Injectable bounded HTTP transport for optional evidence.
public protocol HTTPFetcher: Sendable {
  /// Returns response bytes or throws when the optional evidence cannot be fetched.
  func fetch(_ url: URL) async throws -> Data
}
/// HTTP transport with a short request timeout and response size limit.
public struct URLSessionFetcher: HTTPFetcher {
  private static let requestTimeoutSec: TimeInterval = 3
  private static let maximumResponseBytes = 2_000_000
  /// Creates a URLSessionFetcher with the supplied configuration.
  public init() {}
  /// Fetches a bounded optional-evidence response or throws on transport failure.
  public func fetch(_ url: URL) async throws -> Data {
    var request = URLRequest(url: url); request.timeoutInterval = Self.requestTimeoutSec
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let response = response as? HTTPURLResponse, response.statusCode == 200,
      data.count <= Self.maximumResponseBytes
    else { throw URLError(.badServerResponse) }
    return data
  }
}
/// Caches domain registration ages discovered through IANA RDAP bootstrap data.
public actor RDAPLookup {
  private static let secondsPerDay: TimeInterval = 86_400
  private static let knownLifetimeSec: TimeInterval = 604_800
  private static let unknownLifetimeSec: TimeInterval = 3600
  private static let maximumCachedDomains = 2048
  private let fetcher: any HTTPFetcher
  private let cacheURL: URL?
  private var cache: [String: Entry] = [:]
  private var bootstrap: Bootstrap?
  private var bootstrapExpires = Date.distantPast
  /// Creates a RDAPLookup with the supplied configuration.
  public init(fetcher: any HTTPFetcher = URLSessionFetcher(), cacheURL: URL? = nil) {
    self.fetcher = fetcher; self.cacheURL = cacheURL
    if let cacheURL, let data = try? Data(contentsOf: cacheURL),
      let saved = try? JSONDecoder().decode([String: Entry].self, from: data)
    {
      cache = saved
    }
  }

  private static func registrationDate(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    if let date = formatter.date(from: value) { return date }
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: value)
  }
  /// Returns cached or fetched registration age; failures remain unknown.
  public func ageDays(domain: String, now: Date = .now) async -> Int? {
    guard DomainResolver().registrableDomain(domain) == domain else { return nil }
    if let entry = cache[domain], entry.expires > now {
      return entry.age.map {
        $0 + max(0, Int(now.timeIntervalSince(entry.recordedAt) / Self.secondsPerDay))
      }
    }
    do {
      if bootstrap == nil || bootstrapExpires < now {
        bootstrap = try JSONDecoder().decode(
          Bootstrap.self,
          from: await fetcher.fetch(URL(string: "https://data.iana.org/rdap/dns.json")!)
        )
        bootstrapExpires = now.addingTimeInterval(Self.knownLifetimeSec)
      }
      let tld = String(domain.split(separator: ".").last ?? "")
      guard
        let service = bootstrap?.services.first(where: { $0.count == 2 && $0[0].contains(tld) }),
        let endpoint = service[1].first(where: { $0.hasPrefix("https://") }),
        let base = URL(string: endpoint), base.host != nil
      else {
        save(domain, age: nil, now: now); return nil
      }
      let url = base.appending(path: "domain").appending(path: domain)
      let response = try JSONDecoder().decode(Response.self, from: await fetcher.fetch(url))
      let dates = response.events?.filter { $0.eventAction == "registration" }
        .compactMap { Self.registrationDate($0.eventDate) }
      let age = dates?.min().flatMap {
        $0 <= now ? Int(now.timeIntervalSince($0) / Self.secondsPerDay) : nil
      }
      save(domain, age: age, now: now); return age
    } catch { save(domain, age: nil, now: now); return nil }
  }
  private func save(_ domain: String, age: Int?, now: Date) {
    cache = cache.filter { $0.value.expires > now }
    if cache.count >= Self.maximumCachedDomains, let key = cache.keys.sorted().first {
      cache.removeValue(forKey: key)
    }
    cache[domain] = Entry(
      age: age,
      expires: now.addingTimeInterval(age == nil ? Self.unknownLifetimeSec : Self.knownLifetimeSec),
      recordedAt: now
    )
    if let cacheURL, let data = try? JSONEncoder().encode(cache) {
      try? data.write(to: cacheURL, options: .atomic)
    }
  }

  private struct Entry: Codable { var age: Int?; var expires: Date; var recordedAt: Date }
  private struct Bootstrap: Codable { var services: [[[String]]] }
  private struct Response: Decodable {
    var events: [Event]?
    struct Event: Decodable { var eventAction: String; var eventDate: String }
  }
}
