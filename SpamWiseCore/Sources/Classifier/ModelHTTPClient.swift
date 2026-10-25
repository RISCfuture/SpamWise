public import Foundation
import Signals

/// Injectable HTTP boundary for bounded, credential-bearing model requests.
public struct ModelHTTPClient: Sendable {
  /// Maximum accepted provider response size.
  public static let maximumResponseBytes = 65_536
  /// Ephemeral HTTPS requests with no redirects, cookies, or disk cache.
  public static let live = Self { request in
    do {
      let response = try await transport.send(request)
      return .init(status: response.status, body: response.body)
    } catch BoundedHTTPError.responseTooLarge {
      throw ClassificationError.invalidOutput
    } catch BoundedHTTPError.timeout {
      throw ClassificationError.timeout
    } catch is BoundedHTTPError { throw ClassificationError.network }
  }
  private static let credentialErrorIdentifiers: Set<String> = [
    "API_KEY_INVALID", "invalid_api_key"
  ]
  private static let contextErrorIdentifiers: Set<String> = ["context_length_exceeded"]
  private static let contextErrorMessage = "exceeds the maximum number of tokens"
  private static let transport = BoundedHTTPClient(
    policy: .init(
      maximumResponseBytes: maximumResponseBytes,
      timeout: .seconds(ClassificationLimits.timeoutRange.upperBound),
      acceptedStatusCodes: nil
    )
  )

  private let operation: @Sendable (URLRequest) async throws -> Response

  /// Installs an HTTP operation; fixtures can supply responses without networking.
  public init(_ operation: @escaping @Sendable (URLRequest) async throws -> Response) {
    self.operation = operation
  }

  /**
   Classifies a 400 response by its provider error body.

   An invalid key is a missing credential and an oversized request exceeds the context; every
   other rejection, including an unreadable body, is a configuration error.
   */
  private static func badRequestError(_ body: Data) -> ClassificationError {
    guard let error = try? JSONDecoder().decode(ErrorEnvelope.self, from: body).error else {
      return .configuration
    }
    if !error.identifiers.isDisjoint(with: credentialErrorIdentifiers) { return .missingCredential }
    if !error.identifiers.isDisjoint(with: contextErrorIdentifiers)
      || error.message.contains(contextErrorMessage)
    {
      return .contextExceeded
    }
    return .configuration
  }

  func send(_ request: URLRequest) async throws -> Data {
    let response = try await operation(request)
    guard response.body.count <= Self.maximumResponseBytes else {
      throw ClassificationError.invalidOutput
    }
    switch response.status {
      case 200...299: return response.body
      case 401, 403: throw ClassificationError.missingCredential
      case 408, 504: throw ClassificationError.timeout
      case 429: throw ClassificationError.rateLimited
      case 400: throw Self.badRequestError(response.body)
      case 404, 422: throw ClassificationError.configuration
      default: throw ClassificationError.network
    }
  }

  /// Status and bounded body returned by the injected transport.
  public struct Response: Sendable {
    /// HTTP response status.
    public let status: Int
    /// Raw response bytes, validated before decoding.
    public let body: Data
    /// Creates a transport response.
    public init(status: Int, body: Data) { self.status = status; self.body = body }
  }

  /// An OpenAI or Gemini error response body.
  private struct ErrorEnvelope: Decodable {
    var error: ProviderError

    /// OpenAI's `code` and `type`, or Gemini's `status` and `details[].reason`, with the message.
    struct ProviderError: Decodable {
      var identifiers: Set<String>
      var message: String

      init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let names = [CodingKeys.code, .type, .status].compactMap {
          try? container.decode(String.self, forKey: $0)
        }
        let reasons =
          (try? container.decode([Detail].self, forKey: .details))?
          .compactMap(\.reason) ?? []
        identifiers = Set(names + reasons)
        message = (try? container.decode(String.self, forKey: .message)) ?? ""
      }

      private enum CodingKeys: String, CodingKey { case code, type, status, details, message }
    }

    struct Detail: Decodable { var reason: String? }
  }
}
