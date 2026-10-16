public import Foundation

/// Injectable HTTP boundary for bounded, credential-bearing model requests.
public struct ModelHTTPClient: Sendable {
  /// Maximum accepted provider response size.
  public static let maximumResponseBytes = 65_536
  /// Ephemeral HTTPS requests with no redirects, cookies, or disk cache.
  public static let live = ModelHTTPClient { request in
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieStorage = nil
    configuration.urlCache = nil
    configuration.timeoutIntervalForRequest = 15
    configuration.timeoutIntervalForResource = 15
    let session = URLSession(
      configuration: configuration,
      delegate: RejectModelRedirects(),
      delegateQueue: nil
    )
    defer { session.invalidateAndCancel() }
    let (bytes, response) = try await session.bytes(for: request)
    guard let response = response as? HTTPURLResponse, response.url == request.url else {
      throw ClassificationError.network
    }
    guard response.expectedContentLength <= maximumResponseBytes else {
      throw ClassificationError.invalidOutput
    }
    var body = Data()
    for try await byte in bytes {
      guard body.count < maximumResponseBytes else { throw ClassificationError.invalidOutput }
      body.append(byte)
    }
    return .init(status: response.statusCode, body: body)
  }

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

private final class RejectModelRedirects: NSObject, URLSessionTaskDelegate {
  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) { completionHandler(nil) }
}
