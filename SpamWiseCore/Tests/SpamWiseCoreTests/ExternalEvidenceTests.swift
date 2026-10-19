import Foundation
import Network
import Testing
import SpamWiseCore
@testable import Signals

/// A deadline that only a stalled fixture response can reach, however loaded the machine is.
private let unhurriedDeadline = Duration.seconds(30)

@Test
func `bounds HTTPS responses and sends only domain and header credentials`() async throws {
  let configuration = fixtureConfiguration(SpamhausFixtureProtocol.self)
  let listed = try await SpamhausHTTPS.query(
    domain: "listed.example.org",
    key: "synthetic-key",
    timeout: unhurriedDeadline,
    configuration: configuration
  )
  #expect(listed.addresses == ["127.0.1.4"])
  let rejections: [(domain: String, error: BoundedHTTPError)] = [
    ("large.example.org", .responseTooLarge), ("redirect.example.org", .unexpectedResponse)
  ]
  for (domain, error) in rejections {
    await #expect(throws: error) {
      try await SpamhausHTTPS.query(
        domain: domain,
        key: "synthetic-key",
        timeout: unhurriedDeadline,
        configuration: configuration
      )
    }
  }
}

@Test
func `abandons an HTTPS response that never arrives once its deadline passes`() async {
  let start = ContinuousClock.now
  let error = await #expect(throws: (any Error).self) {
    try await SpamhausHTTPS.query(
      domain: "slow.example.org",
      key: "synthetic-key",
      timeout: .milliseconds(50),
      configuration: fixtureConfiguration(SpamhausFixtureProtocol.self)
    )
  }
  #expect(error.map(isDeadlineExpiry) == true)
  #expect(ContinuousClock.now - start < .seconds(10))
}

/// Whether `error` reports an expired deadline, from the client's own timer or URLSession's.
private func isDeadlineExpiry(_ error: any Error) -> Bool {
  error as? BoundedHTTPError == .timeout || (error as? URLError)?.code == .timedOut
}

@Test
func `interprets only documented HTTPS DBL listings`() async throws {
  let fixtures: [SpamhausResponseFixture] = [
    .init(200, #"{"status":200,"resp":[2002,2004,2104]}"#, .listed),
    .init(404, #"{"status":404}"#, .notListed),
    .init(401, #"{"status":401}"#, .unknown),
    .init(403, #"{"status":403}"#, .unknown),
    .init(429, #"{"status":429}"#, .unknown),
    .init(504, #"{"status":504}"#, .unknown),
    .init(200, #"{"status":200,"resp":[2002,256250]}"#, .unknown),
    .init(200, #"{"status":200,"resp":[3002]}"#, .unknown),
    .init(200, #"{"status":200,"resp":[2003]}"#, .unknown),
    .init(200, #"{"status":200,"resp":[]}"#, .unknown),
    .init(200, #"{"status":404}"#, .unknown),
    .init(404, #"{"status":404,"resp":[2002]}"#, .unknown),
    .init(404, "not JSON", .unknown),
    .init(200, String(repeating: " ", count: 16_385) + #"{"status":200,"resp":[2002]}"#, .unknown),
    .init(200, #"{"status":200,"resp":["2002"]}"#, .unknown)
  ]
  for fixture in fixtures {
    let lookup = SpamhausDomainLookup(
      configuration: .init(termsAcknowledged: true, transport: .https),
      key: { "synthetic-key" },
      httpsQuery: { _, _, _ in
        SpamhausHTTPS.answer(status: fixture.status, data: Data(fixture.body.utf8))
      }
    )
    #expect(await lookup.lookup(domains: ["example.org"]).first?.status == fixture.expected)
  }
  let request = try SpamhausHTTPS.request(domain: "example.org", key: "synthetic-key")
  #expect(request.url?.absoluteString == "https://apibl.spamhaus.net/lookup/v1/DBL/example.org")
  #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-key")
  #expect(request.httpBody == nil)
  #expect(throws: (any Error).self) {
    try SpamhausHTTPS.request(domain: "example.org", key: "bad\r\nheader")
  }
}

/// A consented HTTPS Spamhaus lookup that reads its key and sends its queries through the given boundaries.
private func keyedLookup(
  key: @escaping @Sendable () throws -> String,
  httpsQuery: SpamhausDomainLookup.HTTPSQuery? = nil
) -> SpamhausDomainLookup {
  SpamhausDomainLookup(
    configuration: .init(termsAcknowledged: true, transport: .https),
    key: key,
    httpsQuery: httpsQuery
  )
}

/// A consented lookup whose credential access is recorded as an issue.
private func lookupThatMustNotReadItsKey() -> SpamhausDomainLookup {
  keyedLookup {
    Issue.record("Cancellation and expired budgets must prevent credential access")
    throw KeychainError.missing
  }
}

@Test
func `reads no Spamhaus key without consent`() async {
  let disabled = SpamhausDomainLookup(
    configuration: .init(transport: .https),
    key: {
      Issue.record("No consent must prevent credential access"); return "key"
    }
  )
  #expect(await disabled.lookup(domains: ["example.org"]).isEmpty)
}

@Test
func `sends no keyed query and leaves the domain unknown without a saved key`() async {
  let missing = keyedLookup(
    key: { throw KeychainError.missing },
    httpsQuery: { _, _, _ in
      Issue.record("Missing credentials must not send a request")
      return .init(status: .failed, addresses: [])
    }
  )
  #expect(await missing.lookup(domains: ["example.org"]).first?.status == .unknown)
}

@Test
func `bounds keyed queries by count and deadline`() async {
  let bounded = keyedLookup(
    key: { "synthetic-key" },
    httpsQuery: { domain, key, timeout in
      #expect(!domain.contains("/"))
      #expect(key == "synthetic-key")
      #expect(timeout <= .milliseconds(20))
      try await Task.sleep(for: .seconds(10))
      return .init(status: .answered, addresses: ["127.0.1.2"])
    }
  )
  let domains = (1...10).map { "example\($0).org" } + ["bad/path.org", "127.0.0.1"]
  let start = ContinuousClock.now
  let findings = await bounded.lookup(domains: domains, timeout: 0.02)
  #expect(ContinuousClock.now - start < SpamhausDomainLookup.maximumQueryTime - .seconds(1))
  #expect(findings.map(\.subject) == (1...5).map { "example\($0).org" } + ["5 more domains"])
  #expect(findings.allSatisfy { $0.status == .unknown })
}

@Test(arguments: [0, -1, .infinity, .nan])
func `reads no Spamhaus key once the time budget has run out`(_ timeout: Double) async {
  let lookup = lookupThatMustNotReadItsKey()
  #expect(await lookup.lookup(domains: ["example.org"], timeout: timeout).first?.status == .unknown)
}

@Test
func `reads no Spamhaus key once the lookup is cancelled`() async {
  let lookup = lookupThatMustNotReadItsKey()
  let cancelled = Task {
    try? await Task.sleep(for: .seconds(10))
    return await lookup.lookup(domains: ["example.org"])
  }
  cancelled.cancel()
  #expect(await cancelled.value.first?.status == .unknown)
}

@Test(arguments: ["127.255.255.254", "127.255.255.255", "127.0.1.255", "127.0.1.3", "203.0.113.1"])
func `keeps blocklist error codes out of spam evidence`(_ address: String) async {
  let lookup = SpamhausDomainLookup(
    configuration: .init(termsAcknowledged: true, resolverAddress: "127.0.0.1"),
    query: { _, _ in .init(status: .answered, addresses: [address]) }
  )
  let result = await lookup.lookup(domains: ["example.com"])
  #expect(result.count == 1)
  #expect(result.first?.status == .unknown)
}

@Test
func `requires consent and valid domain names for blocklist queries`() async {
  let disabled = SpamhausDomainLookup(
    configuration: .init(),
    query: { _, _ in
      Issue.record("Disabled blocklists must not query DNS")
      return .init(status: .answered, addresses: ["127.0.1.2"])
    }
  )
  #expect(await disabled.lookup(domains: ["example.com"]).isEmpty)
  let lookup = SpamhausDomainLookup(
    configuration: .init(termsAcknowledged: true, resolverAddress: "127.0.0.1"),
    query: { name, resolver in
      #expect(name == "example.com.dbl.spamhaus.org")
      #expect(resolver == "127.0.0.1")
      return .init(status: .answered, addresses: ["127.0.1.2"])
    }
  )
  let result = await lookup.lookup(domains: [
    "127.0.0.1", "bad;domain.com", "example.com", "example.com"
  ])
  #expect(result.count == 1)
  #expect(result.first?.status == .listed)
  #expect(result.first?.subject == "example.com")
}

@Test
func `posts raw mail to loopback Rspamd and extracts only valid evidence symbols`() async {
  let lookup = RspamdLookup(configuration: fixtureConfiguration(RspamdFixtureProtocol.self))
  let result = await lookup.lookup(raw: RspamdFixtureProtocol.message("valid"))
  #expect(result.status == .observed)
  #expect(result.details == ["BAYES_SPAM: 5.1", "R_DKIM_ALLOW: -0.2"])
  for scenario in [
    "bad-symbol", "excessive-score", "no-symbols", "oversized", "redirect", "failure"
  ] {
    #expect(await lookup.lookup(raw: RspamdFixtureProtocol.message(scenario)).status == .unknown)
  }
  for timeout in [0, -1, .infinity, .nan] {
    let finding = await lookup.lookup(
      raw: RspamdFixtureProtocol.message("expired"),
      timeout: timeout
    )
    #expect(finding.status == .unknown)
  }
}

@Test
func `resolves blocklist answers in process through only the configured resolver`()
  async throws
{
  let resolver = try await LoopbackDNSResolver()
  let listed = await ResolverQuery.addresses(
    of: "listed.example.com.dbl.spamhaus.org",
    resolver: "127.0.0.1",
    port: resolver.port
  )
  #expect(listed.status == .answered)
  #expect(listed.addresses == ["127.0.1.2"])
  let missing = await ResolverQuery.addresses(
    of: "missing.example.com.dbl.spamhaus.org",
    resolver: "127.0.0.1",
    port: resolver.port
  )
  #expect(missing.status == .notFound)
  for address in ["localhost", "127.1", "256.0.0.1", "::1"] {
    let invalid = await ResolverQuery.addresses(
      of: "listed.example.com.dbl.spamhaus.org",
      resolver: address,
      port: resolver.port
    )
    #expect(invalid.status == .failed)
  }
}

@Test
func `decodes saved scanner selections without enabling removed transports`() throws {
  func decoded(_ json: String) throws -> ExternalEvidenceSettings {
    try JSONDecoder().decode(ExternalEvidenceSettings.self, from: Data(json.utf8))
  }
  let base = #""domainBlocklist":false,"termsAcknowledged":false,"resolverAddress":"127.0.0.1""#
  #expect(try decoded("{\(base),\"rspamdTransport\":\"loopbackHTTP\"}").localRspamd)
  #expect(
    try !decoded("{\(base),\"rspamdTransport\":\"executable\",\"rspamcPath\":\"/bin/rspamc\"}")
      .localRspamd
  )
  #expect(try !decoded("{\(base),\"rspamcPath\":\"/bin/rspamc\"}").localRspamd)
  var enabled = ExternalEvidenceSettings()
  enabled.localRspamd = true
  #expect(try decoded(JSONEncoder().encodeText(enabled)) == enabled)
}

private func fixtureConfiguration(_ protocolClass: AnyClass)
  -> @Sendable () -> URLSessionConfiguration
{
  let name = NSStringFromClass(protocolClass)
  return {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [NSClassFromString(name)].compactMap(\.self)
    return configuration
  }
}

private final class SpamhausFixtureProtocol: URLProtocol {
  override static func canInit(with _: URLRequest) -> Bool { true }
  override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    #expect(request.url?.host == "apibl.spamhaus.net")
    #expect(request.url?.scheme == "https")
    #expect(request.url?.query == nil)
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-key")
    #expect(request.httpBody == nil)
    guard let url = request.url else { return }
    let domain = url.lastPathComponent
    if domain == "slow.example.org" { return }
    let status = domain == "redirect.example.org" ? 302 : 200
    let response = HTTPURLResponse(
      url: url,
      statusCode: status,
      httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/json", "Location": "https://example.org/"]
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    let body =
      domain == "large.example.org"
      ? String(repeating: " ", count: 16_385) : #"{"status":200,"resp":[2004]}"#
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

private final class RspamdFixtureProtocol: URLProtocol {
  private static let responses: [String: (status: Int, body: String)] = [
    "valid": (
      200,
      #"""
      {"score":8,"required_score":6,"action":"reject",
       "symbols":{"BAYES_SPAM":{"score":5.1},"R_DKIM_ALLOW":{"score":-0.2}}}
      """#
    ),
    "bad-symbol": (200, #"{"symbols":{"BAD SYMBOL":{"score":1}}}"#),
    "excessive-score": (200, #"{"symbols":{"SPAM":{"score":10001}}}"#),
    "no-symbols": (200, #"{"action":"reject"}"#),
    "oversized": (200, String(repeating: " ", count: 65_537)),
    "redirect": (302, #"{"symbols":{}}"#),
    "failure": (500, #"{"symbols":{}}"#)
  ]

  override static func canInit(with _: URLRequest) -> Bool { true }
  override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  static func message(_ scenario: String) -> Data {
    Data("From: sender@example.org\r\n\r\n\(scenario)".utf8)
  }

  override func startLoading() {
    #expect(request.url?.absoluteString == "http://127.0.0.1:11333/checkv2")
    #expect(request.httpMethod == "POST")
    let scenario = String(data: body(), encoding: .utf8)?.components(separatedBy: "\r\n\r\n").last
    guard let url = request.url, let scenario, let fixture = Self.responses[scenario] else {
      Issue.record("Unexpected Rspamd scan: \(scenario ?? "none")")
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }
    let response = HTTPURLResponse(
      url: url,
      statusCode: fixture.status,
      httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/json", "Location": "http://127.0.0.1:11333/"]
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(fixture.body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}

  private func body() -> Data {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var data = Data(), buffer = [UInt8](repeating: 0, count: 1024)
    while case let count = unsafe stream.read(&buffer, maxLength: buffer.count), count > 0 {
      data.append(contentsOf: buffer.prefix(count))
    }
    return data
  }
}

private struct SpamhausResponseFixture {
  let status: Int
  let body: String
  let expected: ExternalEvidenceStatus

  init(_ status: Int, _ body: String, _ expected: ExternalEvidenceStatus) {
    self.status = status; self.body = body; self.expected = expected
  }
}

/// A UDP resolver on 127.0.0.1 that lists every name except those containing “missing”.
private final class LoopbackDNSResolver: Sendable {
  private static let responseFlag: UInt8 = 0x80, recursionDesiredFlag: UInt8 = 0x01
  private static let recursionAvailableFlag: UInt8 = 0x80, nameErrorCode: UInt8 = 3
  private static let headerFlagsOffset = 2, responseCodeOffset = 3, answerCountOffset = 7
  /// A pointer to the question name, then type A, class IN, a 60-second TTL and 127.0.1.2.
  private static let listedAnswer: [UInt8] = [
    0xC0, 0x0C, 0, 1, 0, 1, 0, 0, 0, 60, 0, 4, 127, 0, 1, 2
  ]
  let port: UInt16
  private let listener: NWListener

  init() async throws {
    let parameters = NWParameters.udp
    parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
    let listener = try NWListener(using: parameters)
    listener.newConnectionHandler = { connection in
      connection.start(queue: .global())
      connection.receiveMessage { query, _, _, _ in
        guard let query else { return }
        connection.send(content: Self.response(to: query), completion: .idempotent)
      }
    }
    port = try await withCheckedThrowingContinuation { continuation in
      listener.stateUpdateHandler = { state in
        switch state {
          case .ready:
            listener.stateUpdateHandler = nil
            continuation.resume(returning: listener.port?.rawValue ?? 0)
          case .failed(let error):
            listener.stateUpdateHandler = nil
            continuation.resume(throwing: error)
          default: break
        }
      }
      listener.start(queue: .global())
    }
    self.listener = listener
  }

  private static func response(to query: Data) -> Data {
    var bytes = [UInt8](query)
    let missing = query.contains(Data("missing".utf8))
    bytes[headerFlagsOffset] = responseFlag | (bytes[headerFlagsOffset] & recursionDesiredFlag)
    bytes[responseCodeOffset] = recursionAvailableFlag | (missing ? nameErrorCode : 0)
    bytes[answerCountOffset] = missing ? 0 : 1
    return Data(missing ? bytes : bytes + listedAnswer)
  }

  deinit { listener.cancel() }
}
