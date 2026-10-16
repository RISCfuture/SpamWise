import Foundation

/// Explicit OpenAI Responses backend using strict structured output and a fresh request per message.
public struct OpenAIClassifier: Classifier {
  /// Supported model whose standard pricing is captured with each response.
  public static let modelID = "gpt-5.4-mini"
  private let selectedModel: String
  private let key: @Sendable () throws -> String
  private let http: ModelHTTPClient

  /// Selects a supported model and injects credentials and an optional HTTP boundary.
  public init(
    modelID: String,
    key: @escaping @Sendable () throws -> String,
    http: ModelHTTPClient = .live
  ) throws {
    guard modelID == Self.modelID else { throw ClassificationError.configuration }
    selectedModel = modelID; self.key = key; self.http = http
  }

  /// Returns a complete validated response; refusals and incomplete output leave mail unclassified.
  public func classify(_ input: ClassificationInput) async throws -> Verdict {
    let request = try RemoteModelRequest.make(
      url: "https://api.openai.com/v1/responses",
      key: key(),
      header: "Authorization",
      body: [
        "model": selectedModel, "store": false, "service_tier": "default",
        "max_output_tokens": 1024,
        "reasoning": ["effort": "low"], "instructions": PromptBuilder.instructions,
        "input": try PromptBuilder.prompt(input),
        "text": [
          "format": [
            "type": "json_schema", "name": "spamwise_verdict", "strict": true,
            "schema": RemoteVerdict.schema
          ]
        ]
      ],
      timeout: input.timeout
    )
    return try await RemoteModelRequest.run(timeout: input.timeout) {
      let data = try await http.send(request)
      let decoder = JSONDecoder()
      decoder.keyDecodingStrategy = .convertFromSnakeCase
      let response = try decoder.decode(OpenAIResponse.self, from: data)
      if response.output?.contains(where: { item in
        item.content?.contains(where: { $0.type == "refusal" }) == true
      }) == true {
        throw ClassificationError.refused
      }
      guard response.status == "completed", let output = response.output else {
        throw ClassificationError.invalidOutput
      }
      let messages = output.filter { $0.type == "message" }
      guard messages.count == 1, let content = messages.first?.content, content.count == 1,
        content.first?.type == "output_text", let text = content.first?.text,
        let measured = response.usage
      else { throw ClassificationError.invalidOutput }
      let usage = try RemoteModelRequest.usage(
        input: measured.inputTokens,
        output: measured.outputTokens,
        cached: measured.inputTokensDetails?.cachedTokens ?? 0,
        modelID: selectedModel
      )
      return try RemoteVerdict.decode(text, usage: usage)
    }
  }
}

private struct OpenAIResponse: Decodable {
  var status: String?
  var output: [Item]?
  var usage: Usage?
  struct Item: Decodable {
    var type: String
    var content: [Content]?
  }
  struct Content: Decodable {
    var type: String
    var text: String?
  }
  struct Usage: Decodable {
    var inputTokens: Int
    var outputTokens: Int
    var inputTokensDetails: Details?
  }
  struct Details: Decodable { var cachedTokens: Int? }
}
