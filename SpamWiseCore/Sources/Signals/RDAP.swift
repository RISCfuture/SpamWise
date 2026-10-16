import Foundation
import MessageModel

public protocol HTTPFetcher: Sendable { func fetch(_ url: URL) async throws -> Data }
public struct URLSessionFetcher: HTTPFetcher {
    public init() {}
    public func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url); request.timeoutInterval = 3
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200, data.count <= 2_000_000 else { throw URLError(.badServerResponse) }
        return data
    }
}
public actor RDAPLookup {
    struct Entry: Codable { var age: Int?; var expires: Date; var recordedAt: Date }
    struct Bootstrap: Codable { var services: [[[String]]] }
    struct Response: Decodable { struct Event: Decodable { var eventAction: String; var eventDate: String }; var events: [Event]? }
    private let fetcher: any HTTPFetcher
    private let cacheURL: URL?
    private var cache: [String: Entry] = [:]
    private var bootstrap: Bootstrap?
    private var bootstrapExpires = Date.distantPast
    public init(fetcher: any HTTPFetcher = URLSessionFetcher(), cacheURL: URL? = nil) {
        self.fetcher = fetcher; self.cacheURL = cacheURL
        if let cacheURL, let data = try? Data(contentsOf: cacheURL), let saved = try? JSONDecoder().decode([String: Entry].self, from: data) { cache = saved }
    }
    public func ageDays(domain: String, now: Date = .now) async -> Int? {
        guard DomainResolver().registrableDomain(domain) == domain else { return nil }
        if let entry = cache[domain], entry.expires > now { return entry.age.map { $0 + max(0, Int(now.timeIntervalSince(entry.recordedAt) / 86_400)) } }
        do {
            if bootstrap == nil || bootstrapExpires < now {
                bootstrap = try JSONDecoder().decode(Bootstrap.self, from: await fetcher.fetch(URL(string: "https://data.iana.org/rdap/dns.json")!))
                bootstrapExpires = now.addingTimeInterval(604_800)
            }
            let tld = String(domain.split(separator: ".").last ?? "")
            guard let service = bootstrap?.services.first(where: { $0.count == 2 && $0[0].contains(tld) }),
                  let endpoint = service[1].first(where: { $0.hasPrefix("https://") }), let base = URL(string: endpoint), base.host != nil else {
                save(domain, age: nil, now: now); return nil
            }
            let url = base.appending(path: "domain").appending(path: domain)
            let response = try JSONDecoder().decode(Response.self, from: await fetcher.fetch(url))
            let dates = response.events?.filter { $0.eventAction == "registration" }.compactMap { event in
                ISO8601DateFormatter().date(from: event.eventDate) ?? {
                    let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return formatter.date(from: event.eventDate)
                }()
            }
            let age = dates?.min().flatMap { $0 <= now ? Int(now.timeIntervalSince($0) / 86_400) : nil }
            save(domain, age: age, now: now); return age
        } catch { save(domain, age: nil, now: now); return nil }
    }
    private func save(_ domain: String, age: Int?, now: Date) {
        cache = cache.filter { $0.value.expires > now }
        if cache.count >= 2048, let key = cache.keys.sorted().first { cache.removeValue(forKey: key) }
        cache[domain] = Entry(age: age, expires: now.addingTimeInterval(age == nil ? 3600 : 604_800), recordedAt: now)
        if let cacheURL, let data = try? JSONEncoder().encode(cache) { try? data.write(to: cacheURL, options: .atomic) }
    }
}
