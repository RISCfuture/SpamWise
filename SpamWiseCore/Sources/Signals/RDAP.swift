public import Foundation
import MessageModel

/// Injectable bounded HTTP transport for optional evidence.
public protocol HTTPFetcher: Sendable {
  /// Returns response bytes or throws when the optional evidence cannot be fetched.
  func fetch(_ url: URL) async throws -> Data
}
extension BoundedHTTPClient: HTTPFetcher {
  /// Returns the body of a successful response.
  package func fetch(_ url: URL) async throws -> Data { try await send(URLRequest(url: url)).body }
}
/**
 Caches domain registration ages discovered through IANA RDAP bootstrap data.

 Only known ages are saved to the cache file. Unknown results, including an unavailable
 bootstrap file, are cached in memory for an hour.
 */
public actor RDAPLookup {
  private static let secondsPerDay: TimeInterval = 86_400
  private static let knownLifetimeSec: TimeInterval = 604_800
  private static let unknownLifetimeSec: TimeInterval = 3600
  private static let maximumCachedDomains = 2048
  private static let bootstrapURL = URL(string: "https://data.iana.org/rdap/dns.json")!
  private static let maximumResponseBytes = 2_000_000
  private static let requestTimeout = Duration.seconds(3)
  private static let policy = BoundedHTTPClient.Policy(
    maximumResponseBytes: maximumResponseBytes,
    timeout: requestTimeout
  )
  private let fetcher: any HTTPFetcher
  private let cacheURL: URL?
  private var cache: [String: Entry] = [:]
  private var persisted: [String: Entry] = [:]
  private var bootstrap: Bootstrap?
  private var bootstrapExpires = Date.distantPast
  private var bootstrapFetch: Task<Bootstrap?, Never>?
  /// Looks up registration data over bounded HTTPS that never follows redirects, reading any cache at `cacheURL` synchronously.
  public init(cacheURL: URL? = nil) {
    self.init(fetcher: BoundedHTTPClient(policy: Self.policy), cacheURL: cacheURL)
  }
  /**
   Looks up registration data through an injected transport, optionally persisting the cache.

   Reads any cache saved at `cacheURL` synchronously; an unreadable cache starts empty.
   */
  public init(fetcher: any HTTPFetcher, cacheURL: URL? = nil) {
    self.fetcher = fetcher; self.cacheURL = cacheURL
    if let cacheURL, let data = try? Data(contentsOf: cacheURL),
      let saved = try? JSONDecoder().decode([String: Entry].self, from: data)
    {
      cache = saved
      persisted = saved.filter { $0.value.age != nil }
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
      let tld = String(domain.split(separator: ".").last ?? "")
      guard
        let service = await currentBootstrap(now: now)?.services.first(where: {
          $0.count == 2 && $0[0].contains(tld)
        }),
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

  /**
   Returns the bootstrap file, fetching it once for every caller when it has expired.

   A failed fetch keeps any earlier file and is retried only after the unknown lifetime.
   */
  private func currentBootstrap(now: Date) async -> Bootstrap? {
    guard bootstrapExpires <= now else { return bootstrap }
    let fetch =
      bootstrapFetch
      ?? Task { [fetcher] in
        try? JSONDecoder().decode(Bootstrap.self, from: await fetcher.fetch(Self.bootstrapURL))
      }
    bootstrapFetch = fetch
    defer { bootstrapFetch = nil }
    if let fetched = await fetch.value {
      bootstrap = fetched
      bootstrapExpires = now.addingTimeInterval(Self.knownLifetimeSec)
    } else {
      bootstrapExpires = now.addingTimeInterval(Self.unknownLifetimeSec)
    }
    return bootstrap
  }

  private func save(_ domain: String, age: Int?, now: Date) {
    cache = cache.filter { $0.value.expires > now }
    if cache.count >= Self.maximumCachedDomains,
      let oldest = cache.min(by: { $0.value.recordedAt < $1.value.recordedAt })?.key
    {
      cache.removeValue(forKey: oldest)
    }
    cache[domain] = Entry(
      age: age,
      expires: now.addingTimeInterval(age == nil ? Self.unknownLifetimeSec : Self.knownLifetimeSec),
      recordedAt: now
    )
    persist()
  }

  /// Writes the known ages to the cache file when they differ from what it holds.
  private func persist() {
    let known = cache.filter { $0.value.age != nil }
    guard let cacheURL, known != persisted, let data = try? JSONEncoder().encode(known) else {
      return
    }
    try? data.write(to: cacheURL, options: .atomic)
    persisted = known
  }

  private struct Entry: Codable, Equatable {
    var age: Int?; var expires: Date; var recordedAt: Date
  }
  private struct Bootstrap: Codable { var services: [[[String]]] }
  private struct Response: Decodable {
    var events: [Event]?

    struct Event: Decodable { var eventAction: String; var eventDate: String }
  }
}
