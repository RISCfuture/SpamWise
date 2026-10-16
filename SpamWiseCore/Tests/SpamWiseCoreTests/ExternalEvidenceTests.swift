import Foundation
import Testing
import SpamWiseCore

@Test(arguments: ["127.255.255.254", "127.255.255.255", "127.0.1.255", "203.0.113.1"])
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
