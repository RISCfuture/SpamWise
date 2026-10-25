import Foundation
import FoundationModels
import Synchronization
import Testing
import SpamWiseCore

private enum CredentialProbe: Error { case requested }

@Test(arguments: [ModelBackend.claude, .openAI, .gemini])
func `reads only the configured provider credential and fails without fallback`(
  _ backend: ModelBackend
) async throws {
  let store = try testStore()
  try await StateRepository.editSettings(store) { settings in
    var advanced = settings.advancedOptions
    advanced.backend = backend
    settings.advancedOptions = advanced
  }
  let classifier = ConfiguredClassifier(store: store) { selected in
    #expect(selected == backend)
    throw CredentialProbe.requested
  }
  await #expect(throws: ClassificationError.consentRequired) {
    _ = try await classifier.classify(providerInput())
  }
  try await StateRepository.editSettings(store) { settings in
    settings.advancedOptions.mailSharingConsent = [backend]
  }
  await #expect(throws: CredentialProbe.requested) {
    _ = try await classifier.classify(providerInput())
  }
  let unsaved = ConfiguredClassifier(store: store) { _ in throw KeychainError.missing }
  await #expect(throws: ClassificationError.missingCredential) {
    _ = try await unsaved.classify(providerInput())
  }
  try await StateRepository.editSettings(store) { settings in
    settings.advancedOptions.mailSharingConsent = []
  }
  await #expect(throws: ClassificationError.consentRequired) {
    _ = try await classifier.classify(providerInput())
  }
  #expect(try await SpendingLimit.load(store).requests == 0)
}

@Test
func `classifies thousands of paid requests by default and settles each to measured usage`()
  async throws
{
  let store = try testStore()
  try await StateRepository.editSettings(store) { settings in
    settings.advancedOptions.backend = .openAI
    settings.advancedOptions.mailSharingConsent = [.openAI]
  }
  let classifier = configuredOpenAI(store: store, response: providerHTTP(openAIResponse))
  let input = try providerInput()
  let requests: UInt = 2_000
  for _ in 0..<requests { _ = try await classifier.classify(input) }
  let measuredMicroUSD: UInt64 = 1_065
  var spending = try await SpendingLimit.load(store)
  #expect(spending.requests == requests)
  #expect(spending.committedMicroUSD == UInt64(requests) * measuredMicroUSD)
  #expect(spending.limitMicroUSD == nil && !spending.limitReached)

  let rateLimited = configuredOpenAI(store: store, response: providerHTTP("", status: 429))
  await #expect(throws: ClassificationError.rateLimited) {
    _ = try await rateLimited.classify(input)
  }
  spending = try await SpendingLimit.load(store)
  #expect(spending.committedMicroUSD == UInt64(requests) * measuredMicroUSD)
}

/// Failures that occur before a provider can bill the request.
private let unbilledFailures: [any Error & Sendable] = [
  ClassificationError.missingCredential, ClassificationError.consentRequired,
  ClassificationError.rateLimited, ClassificationError.contextExceeded,
  ClassificationError.evidenceExceedsPrompt, CancellationError(), StoreError.lockUnavailable
]

@Suite
struct `Spending reservations for paid requests` {
  private static let measuredMicroUSD: UInt64 = 1_065
  private let store: Store
  private let input: ClassificationInput
  private let maximum: Double
  private let measured: Verdict

  /// Sets a limit of two maximum-cost requests, which last month's reservations reached.
  init() async throws {
    store = try testStore()
    input = try providerInput()
    let rates = ModelTokenPricing.rates(for: spendingModel)
    maximum = try rates.maximumCost(of: input)
    measured = Verdict(
      label: .inbox,
      confidence: 93,
      reason: "Personal correspondence",
      usage: .init(
        input: 1_000,
        output: 100,
        cached: 200,
        estimated: false,
        modelID: spendingModel.rawValue,
        pricing: rates
      )
    )
    let lastMonth = try #require(
      Calendar(identifier: .gregorian).date(byAdding: .month, value: -1, to: .now)
    )
    try await SpendingLimit.setLimit(usd: 2 * maximum, store: store, at: lastMonth)
    _ = try await SpendingLimit.reserve(usd: 2 * maximum, store: store, at: lastMonth)
  }

  private func classify(_ outcome: @escaping @Sendable () async throws -> Verdict) async throws {
    _ = try await spendingLimited(store, outcome: outcome).classify(input)
  }

  @Test
  func `reserves a request's maximum cost in a new month and settles it to measured usage`()
    async throws
  {
    let store = store, maximum = maximum, measured = measured
    try await classify {
      let reserved = try await SpendingLimit.load(store).committedUSD
      #expect(abs(reserved - maximum) < 0.000_001)
      return measured
    }
    #expect(try await SpendingLimit.load(store).committedMicroUSD == Self.measuredMicroUSD)
  }

  @Test(arguments: unbilledFailures)
  func `refunds a request that failed before it could be billed`(
    _ failure: any Error & Sendable
  ) async throws {
    let thrown = await #expect(throws: (any Error).self) { try await classify { throw failure } }
    #expect(thrown.map { String(reflecting: $0) } == String(reflecting: failure))
    #expect(try await SpendingLimit.load(store).committedMicroUSD == 0)
  }

  @Test
  func `keeps the maximum cost of a request that may have billed`() async throws {
    await #expect(throws: ClassificationError.network) {
      try await classify { throw ClassificationError.network }
    }
    #expect(abs(try await SpendingLimit.load(store).committedUSD - maximum) < 0.000_001)
  }

  @Test
  func `refuses a request before dispatch once reservations reach the limit`() async throws {
    let measured = measured
    try await classify { measured }
    await #expect(throws: ClassificationError.network) {
      try await classify { throw ClassificationError.network }
    }
    await #expect(throws: SpendingLimitError.limitReached) {
      try await classify {
        Issue.record("The spending limit must refuse the request before dispatch")
        return measured
      }
    }
    let spending = try await SpendingLimit.load(store)
    #expect(abs(spending.committedUSD - 0.001_065 - maximum) < 0.000_001)
    #expect(spending.limitReached && spending.requests == 2)
  }
}

@Test
func `preserves provider pricing through persistence and prices uncaptured usage as Haiku`() throws
{
  let data = Data(
    #"""
    {"input":1000,"output":100,"cached":200,"estimated":false,"modelID":"gpt-5.4-mini",
     "pricing":{"input":0.75,"output":4.5,"cached":0.075,
       "source":"https://developers.openai.com/api/docs/models/gpt-5.4-mini","verified":"2026-10-16"}}
    """#
    .utf8
  )
  let usage = try JSONDecoder().decode(TokenUsage.self, from: data)
  #expect(abs(usage.estimatedCost - 0.001065) < 0.00000001)
  let uncaptured = try JSONDecoder().decode(
    TokenUsage.self,
    from: Data(#"{"input":1000,"output":100,"cached":200,"estimated":false}"#.utf8)
  )
  #expect(abs(uncaptured.estimatedCost - 0.000132) < 0.00000001)
}

func providerInput(timeout: TimeInterval = 15) throws -> ClassificationInput {
  let message = try MIMEParser().parse(fixture("personal"))
  return .init(message: message, evidence: .init(message: message), timeout: timeout)
}

private func configuredOpenAI(store: Store, response: ModelHTTPClient) -> ConfiguredClassifier {
  ConfiguredClassifier(store: store, http: response, credential: { _ in "test-key" })
}

private let spendingModel = ModelIdentifier.gptMini

private func spendingLimited(
  _ store: Store,
  outcome: @escaping @Sendable () async throws -> Verdict
) -> SpendingLimitedClassifier {
  SpendingLimitedClassifier(
    MockClassifier { _ in try await outcome() },
    model: spendingModel,
    store: store
  )
}

private func providerHTTP(_ body: String, status: Int = 200) -> ModelHTTPClient {
  ModelHTTPClient { _ in .init(status: status, body: Data(body.utf8)) }
}

private let openAIResponse =
  #"""
  {"status":"completed","output":[{"type":"message","role":"assistant","content":[
    {"type":"output_text","text":"{\"category\":\"personal\",\"categoryConfidence\":88,\"label\":\"inbox\",\"confidence\":93,\"reason\":\"Personal correspondence\"}"}]}],
    "usage":{"input_tokens":1000,"output_tokens":100,"input_tokens_details":{"cached_tokens":200}}}
  """#

private let geminiResponse =
  #"""
  {"candidates":[{"finishReason":"STOP","content":{"role":"model","parts":[
    {"text":"{\"label\":\"review\",\"confidence\":71,\"reason\":\"Uncertain relationship\"}"}]}}],
    "usageMetadata":{"promptTokenCount":1000,"candidatesTokenCount":80,
      "thoughtsTokenCount":20,"cachedContentTokenCount":200}}
  """#

/// An OpenAI classifier whose provider checks each request with `inspect`, then answers with ``openAIResponse``.
private func openAIClassifier(
  inspecting inspect: @escaping @Sendable (URLRequest) throws -> Void = { _ in }
) -> OpenAIClassifier {
  OpenAIClassifier(
    key: { "fixture" },
    http: ModelHTTPClient { request in
      try inspect(request)
      return .init(status: 200, body: Data(openAIResponse.utf8))
    }
  )
}

/// A Gemini classifier whose provider checks each request with `inspect`, then answers with ``geminiResponse``.
private func geminiClassifier(
  inspecting inspect: @escaping @Sendable (URLRequest) throws -> Void = { _ in }
) -> GeminiClassifier {
  GeminiClassifier(
    key: { "fixture" },
    http: ModelHTTPClient { request in
      try inspect(request)
      return .init(status: 200, body: Data(geminiResponse.utf8))
    }
  )
}

@Test
func `sends OpenAI an unstored bounded request for its model`() async throws {
  let classifier = openAIClassifier { request in
    #expect(request.url?.absoluteString == "https://api.openai.com/v1/responses")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture")
    let body = try #require(request.httpBody)
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(json["model"] as? String == "gpt-5.4-mini")
    #expect(json["store"] as? Bool == false)
    #expect(json["max_output_tokens"] as? Int == 1024)
    #expect(json["previous_response_id"] == nil)
  }
  _ = try await classifier.classify(providerInput())
}

@Test
func `accounts OpenAI usage and cost with cached input`() async throws {
  let result = try await openAIClassifier().classify(providerInput())
  #expect(result.label == .inbox)
  #expect(result.category == .personal && result.categoryConfidence == 88)
  #expect(result.usage.output == 100)
  #expect(result.usage.modelID == "gpt-5.4-mini")
  #expect(abs(result.usage.estimatedCost - 0.001065) < 0.00000001)
}

@Test
func `sends Gemini its key in a header rather than the URL`() async throws {
  let classifier = geminiClassifier { request in
    #expect(request.url?.query == nil)
    #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "fixture")
    #expect(request.url?.path == "/v1beta/models/gemini-3.8-flash:generateContent")
  }
  _ = try await classifier.classify(providerInput())
}

@Test
func `accounts Gemini thinking tokens as output and cached input`() async throws {
  let result = try await geminiClassifier().classify(providerInput())
  #expect(result.label == .review)
  #expect(result.categoryConfidence == nil)
  #expect(result.usage.output == 100)
  #expect(result.usage.cached == 200)
  #expect(result.usage.modelID == "gemini-3.8-flash")
}

@Test(arguments: [
  "{}", "not json", openAIResponse.replacingOccurrences(of: "93", with: "101"),
  openAIResponse.replacingOccurrences(of: "88", with: "101"),
  openAIResponse.replacingOccurrences(of: "completed", with: "incomplete"),
  openAIResponse.replacingOccurrences(of: "\"cached_tokens\":200", with: "\"cached_tokens\":2000")
])
func `rejects malformed or incomplete OpenAI verdicts`(_ response: String) async throws {
  let classifier = OpenAIClassifier(
    key: { "fixture" },
    http: providerHTTP(response)
  )
  await #expect(throws: ClassificationError.invalidOutput) {
    try await classifier.classify(providerInput())
  }
}

@Test(arguments: [
  "{}", "not json", geminiResponse.replacingOccurrences(of: "71", with: "-1"),
  geminiResponse.replacingOccurrences(of: "STOP", with: "MAX_TOKENS"),
  geminiResponse.replacingOccurrences(
    of: "\"thoughtsTokenCount\":20",
    with: "\"thoughtsTokenCount\":-1"
  )
])
func `rejects malformed truncated and invalid Gemini usage responses`(_ response: String)
  async throws
{
  let classifier = GeminiClassifier(
    key: { "fixture" },
    http: providerHTTP(response)
  )
  await #expect(throws: ClassificationError.invalidOutput) {
    try await classifier.classify(providerInput())
  }
}

@Test
func `retains billing provenance after introductory rates end`() throws {
  let introductory = ModelTokenPricing.rates(
    for: .geminiFlash,
    at: Date(timeIntervalSince1970: 1_798_761_599)
  )
  let standard = ModelTokenPricing.rates(
    for: .geminiFlash,
    at: Date(timeIntervalSince1970: 1_798_761_600)
  )
  let usage = TokenUsage(
    input: 1000,
    output: 100,
    cached: 200,
    estimated: false,
    modelID: "gemini-3.8-flash",
    pricing: introductory
  )
  let restored = try JSONDecoder().decode(TokenUsage.self, from: JSONEncoder().encode(usage))
  #expect(abs(restored.estimatedCost - 0.00099) < 0.00000001)
  #expect(standard.input == 1.50)
  let sonnet = TokenUsage(
    input: 1000,
    output: 100,
    cached: 200,
    modelID: "claude-sonnet-5-5",
    pricing: .rates(for: .claudeSonnet)
  )
  #expect(abs(sonnet.estimatedCost - 0.00264) < 0.00000001)
}

@Test
func `rejects provider refusals, rate limits and bad requests without a verdict`() async throws {
  let refused =
    #"{"status":"completed","output":[{"type":"message","content":[{"type":"refusal","refusal":"No"}]}]}"#
  let openAI = OpenAIClassifier(
    key: { "fixture" },
    http: providerHTTP(refused)
  )
  await #expect(throws: ClassificationError.refused) { try await openAI.classify(providerInput()) }
  let gemini = GeminiClassifier(
    key: { "fixture" },
    http: providerHTTP(#"{"promptFeedback":{"blockReason":"SAFETY"}}"#)
  )
  await #expect(throws: ClassificationError.refused) { try await gemini.classify(providerInput()) }
  let limited = GeminiClassifier(
    key: { "fixture" },
    http: providerHTTP("", status: 429)
  )
  await #expect(throws: ClassificationError.rateLimited) {
    try await limited.classify(providerInput())
  }
  for (body, error) in [
    (
      #"{"error":{"code":400,"status":"INVALID_ARGUMENT","details":[{"reason":"API_KEY_INVALID"}]}}"#,
      ClassificationError.missingCredential
    ),
    (#"{"error":{"type":"invalid_request_error","code":"invalid_api_key"}}"#, .missingCredential),
    (#"{"error":{"code":"context_length_exceeded","message":"Too long"}}"#, .contextExceeded),
    (
      #"{"error":{"code":400,"message":"The input token count exceeds the maximum number of tokens allowed"}}"#,
      .contextExceeded
    ),
    (#"{"error":{"code":"model_not_found"}}"#, .configuration), ("Bad request", .configuration)
  ] {
    let rejected = GeminiClassifier(key: { "fixture" }, http: providerHTTP(body, status: 400))
    await #expect(throws: error) { try await rejected.classify(providerInput()) }
  }
}

@Test
func `enforces provider deadlines and response limits`() async throws {
  let slow = OpenAIClassifier(
    key: { "fixture" },
    http: ModelHTTPClient { _ in
      try? await Task.sleep(for: .seconds(60))
      return .init(status: 200, body: Data(openAIResponse.utf8))
    }
  )
  let start = ContinuousClock.now
  await #expect(throws: ClassificationError.timeout) {
    try await slow.classify(providerInput(timeout: 0.01))
  }
  #expect(ContinuousClock.now - start < .seconds(10))
  let oversized = GeminiClassifier(
    key: { "fixture" },
    http: providerHTTP(String(repeating: " ", count: 65_537))
  )
  await #expect(throws: ClassificationError.invalidOutput) {
    try await oversized.classify(providerInput())
  }
}

@Test
func `preserves Apple backend errors and validates session results`() async throws {
  let apple = AppleClassifier(
    backend: .privateCloudCompute,
    generate: { backend, _, _, _ in
      #expect(backend == .privateCloudCompute)
      throw PrivateCloudComputeLanguageModel.Error.quotaLimitReached(
        .init(debugDescription: "Fixture quota")
      )
    }
  )
  await #expect(throws: ClassificationError.rateLimited) {
    try await apple.classify(providerInput())
  }
  let invalid = AppleClassifier(
    backend: .onDevice,
    generate: { _, _, _, _ in
      Verdict(label: .junk, confidence: 101, reason: "Bad confidence")
    }
  )
  await #expect(throws: ClassificationError.invalidOutput) {
    try await invalid.classify(providerInput())
  }
  let refusal = AppleClassifier(
    backend: .onDevice,
    generate: { _, _, _, _ in
      throw LanguageModelError.refusal(
        .init(explanation: "Fixture refusal", debugDescription: "Fixture")
      )
    }
  )
  await #expect(throws: ClassificationError.refused) { try await refusal.classify(providerInput()) }
}

@Test
func `shortens a prompt that exceeds the Apple model's context`() async throws {
  let message = try MIMEParser().parse(
    Data(
      ("From: shop@example.jp\nSubject: お知らせ\n\n"
        + String(repeating: "日本語の長い本文です。", count: 1_500)).utf8
    )
  )
  let input = ClassificationInput(message: message, evidence: .init(message: message), timeout: 15)
  let fitted = Mutex<String?>(nil)
  let verdict = try await appleClassifier(contextTokens: 3_000) { prompt in
    fitted.withLock { $0 = prompt }
  }.classify(input)
  #expect(verdict.label == .review)
  #expect(fitted.withLock { $0 }?.contains("shortenedToFit") == false)
  await #expect(throws: ClassificationError.contextExceeded) {
    try await appleClassifier(contextTokens: 100) { _ in }.classify(input)
  }
}

private func appleClassifier(
  contextTokens: Int,
  fitted: @escaping @Sendable (String) -> Void
) -> AppleClassifier {
  AppleClassifier(
    backend: .onDevice,
    generate: { _, _, prompt, _ in
      let tokens = prompt.unicodeScalars.count
      guard tokens <= contextTokens else {
        throw LanguageModelError.contextSizeExceeded(
          .init(contextSize: contextTokens, tokenCount: tokens, debugDescription: "Fixture")
        )
      }
      fitted(prompt)
      return Verdict(label: .review, confidence: 60, reason: "Shortened")
    }
  )
}
