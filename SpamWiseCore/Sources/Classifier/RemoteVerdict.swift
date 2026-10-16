import Foundation

struct RemoteVerdict: Decodable {
  var label: MailLabel
  var confidence: Int
  var reason: String

  static var schema: [String: Any] {
    [
      "type": "object", "additionalProperties": false,
      "required": ["label", "confidence", "reason"],
      "properties": [
        "label": ["type": "string", "enum": ["inbox", "review", "junk"]],
        "confidence": ["type": "integer", "minimum": 0, "maximum": 100],
        "reason": ["type": "string", "minLength": 1, "maxLength": 240]
      ]
    ]
  }

  static func decode(_ text: String, usage: TokenUsage) throws -> Verdict {
    guard text.utf8.count <= 4096 else { throw ClassificationError.invalidOutput }
    let value = try JSONDecoder().decode(Self.self, from: Data(text.utf8))
    guard value.reason.count <= 240 else { throw ClassificationError.invalidOutput }
    return try Verdict(
      label: value.label,
      confidence: value.confidence,
      reason: value.reason,
      usage: usage
    ).validated()
  }
}

enum RemoteModelRequest {
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
    var request = URLRequest(url: url, timeoutInterval: min(15, max(0.01, timeout)))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(header == "Authorization" ? "Bearer \(key)" : key, forHTTPHeaderField: header)
    request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    guard (request.httpBody?.count ?? 0) <= 262_144 else {
      throw ClassificationError.contextExceeded
    }
    return request
  }

  static func run(timeout: TimeInterval, operation: @escaping @Sendable () async throws -> Verdict)
    async throws -> Verdict
  {
    do {
      return try await withDeadline(seconds: min(15, max(0.01, timeout)), operation: operation)
    } catch is CancellationError { throw ClassificationError.cancelled } catch let error
      as ClassificationError
    { throw error } catch is DecodingError { throw ClassificationError.invalidOutput } catch let
      error as URLError
    {
      switch error.code {
        case .timedOut: throw ClassificationError.timeout
        case .cancelled: throw ClassificationError.cancelled
        default: throw ClassificationError.network
      }
    } catch { throw ClassificationError.network }
  }

  static func usage(input: Int, output: Int, cached: Int, modelID: String) throws -> TokenUsage {
    guard input >= 0, output >= 0, cached >= 0, cached <= input,
      input <= 1_000_000, output <= 100_000
    else { throw ClassificationError.invalidOutput }
    return .init(
      input: input,
      output: output,
      cached: cached,
      estimated: false,
      modelID: modelID,
      pricing: try .rates(for: modelID)
    )
  }
}
