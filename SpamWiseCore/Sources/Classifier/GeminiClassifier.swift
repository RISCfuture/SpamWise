import Foundation

/// Explicit Gemini REST backend with a single candidate, bounded output and isolated instructions.
public struct GeminiClassifier: Classifier {
  /// Supported model whose standard pricing is captured with each response.
  public static let modelID = "gemini-3.8-flash"
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

  /// Returns only a completed, non-blocked verdict; blocked or truncated output fails open.
  public func classify(_ input: ClassificationInput) async throws -> Verdict {
    let request = try RemoteModelRequest.make(
      url:
        "https://generativelanguage.googleapis.com/v1beta/models/\(selectedModel):generateContent",
      key: key(),
      header: "x-goog-api-key",
      body: [
        "systemInstruction": ["parts": [["text": PromptBuilder.instructions]]],
        "contents": [["role": "user", "parts": [["text": try PromptBuilder.prompt(input)]]]],
        "generationConfig": [
          "candidateCount": 1, "maxOutputTokens": ClassificationLimits.maximumResponseTokens,
          "responseMimeType": "application/json", "responseJsonSchema": RemoteVerdict.schema,
          "thinkingConfig": ["thinkingLevel": "low"]
        ]
      ],
      timeout: input.timeout
    )
    return try await RemoteModelRequest.run(timeout: input.timeout) {
      let data = try await http.send(request)
      let response = try JSONDecoder().decode(GeminiResponse.self, from: data)
      if let block = response.promptFeedback?.blockReason, block != "BLOCK_REASON_UNSPECIFIED" {
        throw ClassificationError.refused
      }
      guard let candidates = response.candidates, candidates.count == 1,
        let candidate = candidates.first
      else { throw ClassificationError.invalidOutput }
      if ["SAFETY", "RECITATION", "BLOCKLIST", "PROHIBITED_CONTENT", "SPII", "IMAGE_SAFETY"]
        .contains(candidate.finishReason)
      {
        throw ClassificationError.refused
      }
      guard candidate.finishReason == "STOP", let parts = candidate.content?.parts,
        parts.count == 1, parts.first?.thought != true, let text = parts.first?.text,
        let measured = response.usageMetadata
      else { throw ClassificationError.invalidOutput }
      let thoughts = measured.thoughtsTokenCount ?? 0
      guard (0...ClassificationLimits.maximumOutputTokens).contains(thoughts),
        (0...ClassificationLimits.maximumOutputTokens).contains(measured.candidatesTokenCount)
      else {
        throw ClassificationError.invalidOutput
      }
      let usage = try RemoteModelRequest.usage(
        input: measured.promptTokenCount,
        output: measured.candidatesTokenCount + thoughts,
        cached: measured.cachedContentTokenCount ?? 0,
        modelID: selectedModel
      )
      return try RemoteVerdict.decode(text, usage: usage)
    }
  }
}

private struct GeminiResponse: Decodable {
  var candidates: [Candidate]?
  var promptFeedback: Feedback?
  var usageMetadata: Usage?
  struct Candidate: Decodable { var finishReason: String; var content: Content? }
  struct Content: Decodable { var parts: [Part] }
  struct Part: Decodable { var text: String?; var thought: Bool? }
  struct Feedback: Decodable { var blockReason: String? }
  struct Usage: Decodable {
    var promptTokenCount: Int
    var candidatesTokenCount: Int
    var thoughtsTokenCount: Int?
    var cachedContentTokenCount: Int?
  }
}
