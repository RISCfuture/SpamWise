import Foundation
import FoundationModels
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

@Test
func `reserves each paid request’s maximum cost and refunds only requests that cannot have billed`()
  async throws
{
  let store = try testStore()
  let input = try providerInput()
  let rates = ModelTokenPricing.rates(for: spendingModel)
  let maximum = try rates.maximumCost(of: input)
  let measured = Verdict(
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

  _ = try await spendingLimited(store) {
    let reserved = try await SpendingLimit.load(store).committedUSD
    #expect(abs(reserved - maximum) < 0.000_001)
    return measured
  }
  .classify(input)
  #expect(try await SpendingLimit.load(store).committedMicroUSD == 1_065)

  let unbilled: [any Error & Sendable] = [
    ClassificationError.missingCredential, ClassificationError.consentRequired,
    ClassificationError.rateLimited, ClassificationError.contextExceeded, CancellationError(),
    StoreError.lockUnavailable
  ]
  for failure in unbilled {
    let thrown = await #expect(throws: (any Error).self) {
      _ = try await spendingLimited(store) { throw failure }.classify(input)
    }
    #expect(thrown.map { String(reflecting: $0) } == String(reflecting: failure))
  }
  #expect(try await SpendingLimit.load(store).committedMicroUSD == 1_065)

  await #expect(throws: ClassificationError.network) {
    _ = try await spendingLimited(store) { throw ClassificationError.network }.classify(input)
  }
  await #expect(throws: SpendingLimitError.limitReached) {
    _ = try await spendingLimited(store) {
      Issue.record("The spending limit must refuse the request before dispatch")
      return measured
    }
    .classify(input)
  }
  let spending = try await SpendingLimit.load(store)
  #expect(abs(spending.committedUSD - 0.001_065 - maximum) < 0.000_001)
  #expect(spending.limitReached && spending.requests == 8)
}

@Test
func `preserves provider pricing through persistence and migrates legacy usage`() throws {
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
  let legacy = try JSONDecoder().decode(
    TokenUsage.self,
    from: Data(#"{"input":1000,"output":100,"cached":200,"estimated":false}"#.utf8)
  )
  #expect(abs(legacy.estimatedCost - 0.000132) < 0.00000001)
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
    {"type":"output_text","text":"{\"label\":\"inbox\",\"confidence\":93,\"reason\":\"Personal correspondence\"}"}]}],
    "usage":{"input_tokens":1000,"output_tokens":100,"input_tokens_details":{"cached_tokens":200}}}
  """#

private let geminiResponse =
  #"""
  {"candidates":[{"finishReason":"STOP","content":{"role":"model","parts":[
    {"text":"{\"label\":\"review\",\"confidence\":71,\"reason\":\"Uncertain relationship\"}"}]}}],
    "usageMetadata":{"promptTokenCount":1000,"candidatesTokenCount":80,
      "thoughtsTokenCount":20,"cachedContentTokenCount":200}}
  """#

@Test
func `encodes isolated provider requests and accounts for billed tokens`()
  async throws
{
  let openAI = OpenAIClassifier(
    key: { "fixture" },
    http: ModelHTTPClient { request in
      #expect(request.url?.absoluteString == "https://api.openai.com/v1/responses")
      #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture")
      let body = try #require(request.httpBody)
      let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
      #expect(json["model"] as? String == "gpt-5.4-mini")
      #expect(json["store"] as? Bool == false)
      #expect(json["max_output_tokens"] as? Int == 1024)
      #expect(json["previous_response_id"] == nil)
      return .init(status: 200, body: Data(openAIResponse.utf8))
    }
  )
  let result = try await openAI.classify(providerInput())
  #expect(result.label == .inbox)
  #expect(result.usage.output == 100)
  #expect(result.usage.modelID == "gpt-5.4-mini")
  #expect(abs(result.usage.estimatedCost - 0.001065) < 0.00000001)
  let gemini = GeminiClassifier(
    key: { "fixture" },
    http: ModelHTTPClient { request in
      #expect(request.url?.query == nil)
      #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "fixture")
      #expect(request.url?.path == "/v1beta/models/gemini-3.8-flash:generateContent")
      return .init(status: 200, body: Data(geminiResponse.utf8))
    }
  )
  let googleResult = try await gemini.classify(providerInput())
  #expect(googleResult.label == .review)
  #expect(googleResult.usage.output == 100)
  #expect(googleResult.usage.cached == 200)
  #expect(googleResult.usage.modelID == "gemini-3.8-flash")
}

@Test(arguments: [
  "{}", "not json", openAIResponse.replacingOccurrences(of: "93", with: "101"),
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
  #expect(abs(sonnet.estimatedCost - 0.00262) < 0.00000001)
}

@Test
func `rejects provider refusals and rate limits without a verdict`() async throws {
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
}

@Test
func `enforces provider deadlines and response limits`() async throws {
  let slow = OpenAIClassifier(
    key: { "fixture" },
    http: ModelHTTPClient { _ in
      try? await Task.sleep(for: .seconds(1))
      return .init(status: 200, body: Data(openAIResponse.utf8))
    }
  )
  await #expect(throws: ClassificationError.timeout) {
    try await slow.classify(providerInput(timeout: 0.01))
  }
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
