import Foundation

struct RemoteVerdict: Decodable {
  private static let maximumEncodedBytes = 4096
  static var schema: [String: Any] {
    [
      "type": "object", "additionalProperties": false,
      "required": ["label", "confidence", "reason"],
      "properties": [
        "label": ["type": "string", "enum": ["inbox", "review", "junk"]],
        "confidence": [
          "type": "integer", "minimum": ClassificationLimits.confidenceRange.lowerBound,
          "maximum": ClassificationLimits.confidenceRange.upperBound
        ],
        "reason": [
          "type": "string", "minLength": 1,
          "maxLength": ClassificationLimits.maximumReasonCharacters
        ]
      ]
    ]
  }

  var label: MailLabel
  var confidence: Int
  var reason: String

  static func decode(_ text: String, usage: TokenUsage) throws -> Verdict {
    guard text.utf8.count <= maximumEncodedBytes else { throw ClassificationError.invalidOutput }
    let value = try JSONDecoder().decode(Self.self, from: Data(text.utf8))
    guard value.reason.count <= ClassificationLimits.maximumReasonCharacters else {
      throw ClassificationError.invalidOutput
    }
    return try Verdict(
      label: value.label,
      confidence: value.confidence,
      reason: value.reason,
      usage: usage
    ).validated()
  }
}

enum RemoteModelRequest {
  private static let maximumRequestBytes = 262_144

  private static func boundedTimeout(_ timeout: TimeInterval) -> TimeInterval {
    min(
      ClassificationLimits.timeoutRange.upperBound,
      max(ClassificationLimits.timeoutRange.lowerBound, timeout)
    )
  }

  static func make(
    url: String,
    key: String,
    header: String,
    body: [String: Any],
    timeout: TimeInterval
  ) throws -> URLRequest {
    guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !key.contains("\r"), !key.contains("\n")
    else { throw ClassificationError.missingCredential }
    guard let url = URL(string: url) else { throw ClassificationError.configuration }
    var request = URLRequest(url: url, timeoutInterval: boundedTimeout(timeout))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(header == "Authorization" ? "Bearer \(key)" : key, forHTTPHeaderField: header)
    request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    guard (request.httpBody?.count ?? 0) <= maximumRequestBytes else {
      throw ClassificationError.contextExceeded
    }
    return request
  }

  static func run(timeout: TimeInterval, operation: @escaping @Sendable () async throws -> Verdict)
    async throws -> Verdict
  {
    do {
      return try await withDeadline(seconds: boundedTimeout(timeout), operation: operation)
    } catch { throw ClassificationError(mapping: error) }
  }

  static func usage(input: Int, output: Int, cached: Int, model: ModelIdentifier) throws
    -> TokenUsage
  {
    guard input >= 0, output >= 0, cached >= 0, cached <= input,
      input <= ClassificationLimits.maximumInputTokens,
      output <= ClassificationLimits.maximumOutputTokens
    else { throw ClassificationError.invalidOutput }
    return .init(
      input: input,
      output: output,
      cached: cached,
      estimated: false,
      modelID: model.rawValue,
      pricing: .rates(for: model)
    )
  }
}
