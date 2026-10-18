public import Foundation
import Signals

/// Injectable HTTP boundary for bounded, credential-bearing model requests.
public struct ModelHTTPClient: Sendable {
  /// Maximum accepted provider response size.
  public static let maximumResponseBytes = 65_536
  /// Ephemeral HTTPS requests with no redirects, cookies, or disk cache.
  public static let live = ModelHTTPClient { request in
    do {
      let response = try await transport.send(request)
      return .init(status: response.status, body: response.body)
    } catch BoundedHTTPError.responseTooLarge {
      throw ClassificationError.invalidOutput
    } catch BoundedHTTPError.timeout {
      throw ClassificationError.timeout
    } catch is BoundedHTTPError { throw ClassificationError.network }
  }
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
      case 400, 404, 422: throw ClassificationError.configuration
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
}
