import Foundation
import FoundationModels
import Testing
import SpamWiseCore

private enum CredentialProbe: Error { case requested }

@Test(arguments: [ModelBackend.claude, .openAI, .gemini])
func `configured provider reads only its explicit credential and fails without fallback`(
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
  await #expect(throws: CredentialProbe.requested) {
    _ = try await classifier.classify(providerInput())
  }
}

@Test func `provider pricing survives persistence without charging Haiku rates`() throws {
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

private func providerInput(timeout: TimeInterval = 15) throws -> ClassificationInput {
  let message = try MIMEParser().parse(fixture("personal"))
  return .init(message: message, evidence: .init(message: message), timeout: timeout)
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

@Test func `remote providers encode isolated structured requests and account for billed tokens`()
  async throws
{
  let openAI = try OpenAIClassifier(
    modelID: "gpt-5.4-mini",
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
  let gemini = try GeminiClassifier(
    modelID: "gemini-3.8-flash",
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
func `openai rejects malformed or incomplete verdicts`(_ response: String) async throws {
  let classifier = try OpenAIClassifier(
    modelID: "gpt-5.4-mini",
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
func `gemini rejects malformed truncated and invalid usage responses`(_ response: String)
  async throws
{
  let classifier = try GeminiClassifier(
    modelID: "gemini-3.8-flash",
    key: { "fixture" },
    http: providerHTTP(response)
  )
  await #expect(throws: ClassificationError.invalidOutput) {
    try await classifier.classify(providerInput())
  }
}

@Test func `captured prices retain billing provenance after introductory rates end`() throws {
  let introductory = try ModelTokenPricing.rates(
    for: "gemini-3.8-flash",
    at: Date(timeIntervalSince1970: 1_798_761_599)
  )
  let standard = try ModelTokenPricing.rates(
    for: "gemini-3.8-flash",
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
    pricing: try .rates(for: "claude-sonnet-5-5")
  )
  #expect(abs(sonnet.estimatedCost - 0.00262) < 0.00000001)
}

@Test func `providers reject refusals and rate limits without a verdict`() async throws {
  let refused =
    #"{"status":"completed","output":[{"type":"message","content":[{"type":"refusal","refusal":"No"}]}]}"#
  let openAI = try OpenAIClassifier(
    modelID: "gpt-5.4-mini",
    key: { "fixture" },
    http: providerHTTP(refused)
  )
  await #expect(throws: ClassificationError.refused) { try await openAI.classify(providerInput()) }
  let gemini = try GeminiClassifier(
    modelID: "gemini-3.8-flash",
    key: { "fixture" },
    http: providerHTTP(#"{"promptFeedback":{"blockReason":"SAFETY"}}"#)
  )
  await #expect(throws: ClassificationError.refused) { try await gemini.classify(providerInput()) }
  let limited = try GeminiClassifier(
    modelID: "gemini-3.8-flash",
    key: { "fixture" },
    http: providerHTTP("", status: 429)
  )
  await #expect(throws: ClassificationError.rateLimited) {
    try await limited.classify(providerInput())
  }
}

@Test func `providers enforce deadline response limits and explicit model selection`() async throws
{
  let slow = try OpenAIClassifier(
    modelID: "gpt-5.4-mini",
    key: { "fixture" },
    http: ModelHTTPClient { _ in
      try? await Task.sleep(for: .seconds(1))
      return .init(status: 200, body: Data(openAIResponse.utf8))
    }
  )
  await #expect(throws: ClassificationError.timeout) {
    try await slow.classify(providerInput(timeout: 0.01))
  }
  let oversized = try GeminiClassifier(
    modelID: "gemini-3.8-flash",
    key: { "fixture" },
    http: providerHTTP(String(repeating: " ", count: 65_537))
  )
  await #expect(throws: ClassificationError.invalidOutput) {
    try await oversized.classify(providerInput())
  }
  #expect(throws: ClassificationError.configuration) {
    try OpenAIClassifier(modelID: "other", key: { "fixture" })
  }
  #expect(throws: ClassificationError.configuration) {
    try GeminiClassifier(modelID: "../models/other", key: { "fixture" })
  }
}

@Test func `apple adapter preserves backend errors and caps session results`() async throws {
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
