import Foundation
import Testing
import SpamWiseCore
@testable import Signals

@Test func `bounds HTTPS responses and sends only domain and header credentials`() async throws {
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [SpamhausFixtureProtocol.self]
  let listed = try await SpamhausHTTPS.query(
    domain: "listed.example.org",
    key: "synthetic-key",
    timeout: 0.5,
    configuration: configuration
  )
  #expect(listed.addresses == ["127.0.1.4"])
  for domain in ["large.example.org", "redirect.example.org", "slow.example.org"] {
    await #expect(throws: (any Error).self) {
      try await SpamhausHTTPS.query(
        domain: domain,
        key: "synthetic-key",
        timeout: 0.05,
        configuration: configuration
      )
    }
  }
}

@Test func `interprets only documented HTTPS DBL listings`() async throws {
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

@Test func `bounds keyed queries and leaves unavailable credentials unknown`() async {
  let disabled = SpamhausDomainLookup(
    configuration: .init(transport: .https),
    key: {
      Issue.record("No consent must prevent credential access"); return "key"
    }
  )
  #expect(await disabled.lookup(domains: ["example.org"]).isEmpty)
  let missing = SpamhausDomainLookup(
    configuration: .init(termsAcknowledged: true, transport: .https),
    key: { throw KeychainError.missing },
    httpsQuery: { _, _, _ in
      Issue.record("Missing credentials must not send a request")
      return .init(status: .failed, addresses: [])
    }
  )
  #expect(await missing.lookup(domains: ["example.org"]).first?.status == .unknown)
  let bounded = SpamhausDomainLookup(
    configuration: .init(termsAcknowledged: true, transport: .https),
    key: { "synthetic-key" },
    httpsQuery: { domain, key, timeout in
      #expect(!domain.contains("/"))
      #expect(key == "synthetic-key")
      #expect(timeout <= 0.02)
      try await Task.sleep(for: .seconds(1))
      return .init(status: .answered, addresses: ["127.0.1.2"])
    }
  )
  let domains = (1...10).map { "example\($0).org" } + ["bad/path.org", "127.0.0.1"]
  let start = ContinuousClock.now
  let findings = await bounded.lookup(domains: domains, timeout: 0.02)
  #expect(ContinuousClock.now - start < .seconds(0.5))
  #expect(findings.count == 5)
  #expect(findings.allSatisfy { $0.status == .unknown })
  let expired = SpamhausDomainLookup(
    configuration: .init(termsAcknowledged: true, transport: .https),
    key: {
      Issue.record("Cancellation and expired budgets must prevent credential access")
      throw KeychainError.missing
    }
  )
  for timeout in [0, -1, .infinity, .nan] {
    #expect(
      await expired.lookup(domains: ["example.org"], timeout: timeout).first?.status == .unknown
    )
  }
  let cancelled = Task {
    try? await Task.sleep(for: .seconds(10))
    return await expired.lookup(domains: ["example.org"])
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

@Test func `requires consent and valid domain names for blocklist queries`() async {
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

@Test func `passes raw mail to Rspamd through stdin and extracts evidence symbols`() async throws {
  let raw = Data("From: sender@example.org\r\n\r\n$(touch /tmp/unwanted)".utf8)
  let process = EvidenceProcess { executable, arguments, input in
    #expect(executable == "/opt/homebrew/bin/rspamc")
    #expect(arguments == ["--json", "--connect=127.0.0.1:11333", "--timeout=2", "symbols"])
    #expect(input == raw)
    return Data(
      #"""
      {"score":8,"required_score":6,"action":"reject",
       "symbols":{"BAYES_SPAM":{"score":5.1},"R_DKIM_ALLOW":{"score":-0.2}}}
      """#
      .utf8
    )
  }
  let lookup = RspamdLookup(executablePath: "/opt/homebrew/bin/rspamc", process: process)
  let result = await lookup.lookup(raw: raw)
  #expect(result.status == .observed)
  #expect(result.details.contains("BAYES_SPAM: 5.1"))
  #expect(!result.details.contains("reject"))
  let failed = RspamdLookup(
    executablePath: "/opt/homebrew/bin/rspamc",
    process: EvidenceProcess { _, _, _ in
      throw CocoaError(.fileReadNoPermission)
    }
  )
  #expect(await failed.lookup(raw: raw).status == .unknown)
  for response in [
    #"{"symbols":{"BAD SYMBOL":{"score":1}}}"#,
    #"{"symbols":{"SPAM":{"score":10001}}}"#,
    #"{"action":"reject"}"#,
    String(repeating: " ", count: 65_537)
  ] {
    let malformed = RspamdLookup(
      executablePath: "/opt/homebrew/bin/rspamc",
      process: EvidenceProcess { _, _, _ in Data(response.utf8) }
    )
    #expect(await malformed.lookup(raw: raw).status == .unknown)
  }
  let missingPath = RspamdLookup(
    transport: .executable,
    process: EvidenceProcess { _, _, _ in
      Issue.record("Missing executable selection must not dispatch a scan")
      return Data()
    }
  )
  #expect(await missingPath.lookup(raw: raw).status == .unknown)
  let expired = RspamdLookup(
    executablePath: "/opt/homebrew/bin/rspamc",
    process: EvidenceProcess { _, _, _ in
      Issue.record("Expired scan budgets must not dispatch a scan")
      return Data()
    }
  )
  for timeout in [0, -1, .infinity, .nan] {
    #expect(await expired.lookup(raw: raw, timeout: timeout).status == .unknown)
  }
}

@Test func `preserves process input and stops output floods and timeouts`() async throws {
  let echoed = try await EvidenceProcess.live.run(
    executable: "/bin/cat",
    arguments: [],
    input: Data("fixture".utf8)
  )
  #expect(echoed == Data("fixture".utf8))
  await #expect(throws: EvidenceProcessError.outputLimit) {
    try await EvidenceProcess.live.run(executable: "/usr/bin/yes", arguments: [], input: Data())
  }
  await #expect(throws: EvidenceProcessError.timeout) {
    try await EvidenceProcess.live.run(executable: "/bin/sleep", arguments: ["10"], input: Data())
  }
}

private final class SpamhausFixtureProtocol: URLProtocol {
  override static func canInit(with request: URLRequest) -> Bool { true }
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

private struct SpamhausResponseFixture {
  let status: Int
  let body: String
  let expected: ExternalEvidenceStatus

  init(_ status: Int, _ body: String, _ expected: ExternalEvidenceStatus) {
    self.status = status; self.body = body; self.expected = expected
  }
}
