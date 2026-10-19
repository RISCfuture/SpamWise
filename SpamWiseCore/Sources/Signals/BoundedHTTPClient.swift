package import Foundation
import MessageModel

/// A bounded request failure; callers map it to their own unknown or error result.
package enum BoundedHTTPError: Error, Equatable {
  case unexpectedResponse, responseTooLarge, timeout
}

/**
 Sends one request through a fresh ephemeral session that never follows redirects, stores
 cookies, credentials or cache entries, or buffers more than the policy's byte limit.

 Callers differ only through ``Policy``. Model providers, Spamhaus and RDAP reach public HTTPS
 services, so they honor system proxies and accept only server-trust challenges. The local
 Rspamd scanner is plain HTTP on the loopback interface, so it bypasses proxies (message data
 must not leave the Mac) and rejects every authentication challenge.
 */
package struct BoundedHTTPClient: Sendable {
  private static var noProxies: [AnyHashable: Any] {
    [
      "HTTPEnable": 0, "HTTPSEnable": 0, "SOCKSEnable": 0,
      "ProxyAutoConfigEnable": 0, "ProxyAutoDiscoveryEnable": 0
    ]
  }
  private let policy: Policy
  private let configuration: @Sendable () -> URLSessionConfiguration

  /// Creates a client; tests can supply a configuration with fixture protocol classes.
  package init(
    policy: Policy,
    configuration: @escaping @Sendable () -> URLSessionConfiguration = { .ephemeral }
  ) {
    self.policy = policy; self.configuration = configuration
  }

  /// Returns the status and bounded body, within the policy timeout or a shorter caller budget.
  package func send(_ request: URLRequest, timeout: Duration? = nil) async throws -> Response {
    let timeout = min(timeout ?? policy.timeout, policy.timeout)
    let seconds = timeout / .seconds(1)
    let session = URLSession(
      configuration: sessionConfiguration(timeout: seconds),
      delegate: RedirectRefusingDelegate(challenges: policy.challenges),
      delegateQueue: nil
    )
    defer { session.invalidateAndCancel() }
    do {
      return try await withTaskCancellationHandler {
        try await withResourceDeadline(seconds: seconds) {
          let (bytes, response) = try await session.bytes(for: request)
          let status = try validatedStatus(response, for: request)
          return Response(status: status, body: try await collect(bytes))
        }
      } onCancel: {
        session.invalidateAndCancel()
      }
    } catch ResourceDeadlineError.timeout { throw BoundedHTTPError.timeout }
  }

  private func sessionConfiguration(timeout: TimeInterval) -> URLSessionConfiguration {
    let configuration = configuration()
    if policy.proxies == .direct { configuration.connectionProxyDictionary = Self.noProxies }
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.urlCredentialStorage = nil
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.timeoutIntervalForRequest = timeout
    configuration.timeoutIntervalForResource = timeout
    configuration.waitsForConnectivity = false
    return configuration
  }

  private func validatedStatus(_ response: URLResponse, for request: URLRequest) throws -> Int {
    guard let response = response as? HTTPURLResponse, response.url == request.url,
      policy.acceptedStatusCodes?.contains(response.statusCode) ?? true,
      policy.mimeType.map({ response.mimeType?.lowercased() == $0 }) ?? true
    else { throw BoundedHTTPError.unexpectedResponse }
    guard response.expectedContentLength <= policy.maximumResponseBytes else {
      throw BoundedHTTPError.responseTooLarge
    }
    return response.statusCode
  }

  private func collect(_ bytes: URLSession.AsyncBytes) async throws -> Data {
    var body = Data()
    for try await byte in bytes {
      try Task.checkCancellation()
      guard body.count < policy.maximumResponseBytes else {
        throw BoundedHTTPError.responseTooLarge
      }
      body.append(byte)
    }
    return body
  }

  /// Limits and trust choices for one kind of request.
  package struct Policy: Sendable {
    /// Largest accepted body, enforced while streaming.
    package var maximumResponseBytes: Int
    /// Wall-clock limit for the whole request, including the streamed body.
    package var timeout: Duration
    /// Accepted HTTP statuses; nil returns every status for the caller to interpret.
    package var acceptedStatusCodes: Set<Int>?
    /// Required lowercase response media type, if any.
    package var mimeType: String?
    /// Whether the request may use the system proxy configuration.
    package var proxies: ProxyPolicy
    /// Which authentication challenges receive default handling.
    package var challenges: ChallengePolicy

    /// Creates a policy; public HTTPS services keep the system proxy and server-trust defaults.
    package init(
      maximumResponseBytes: Int,
      timeout: Duration,
      acceptedStatusCodes: Set<Int>? = [200],
      mimeType: String? = nil,
      proxies: ProxyPolicy = .system,
      challenges: ChallengePolicy = .serverTrustOnly
    ) {
      self.maximumResponseBytes = maximumResponseBytes; self.timeout = timeout
      self.acceptedStatusCodes = acceptedStatusCodes; self.mimeType = mimeType
      self.proxies = proxies; self.challenges = challenges
    }
  }

  /// Proxy routing for a request.
  package enum ProxyPolicy: Sendable {
    /// Uses the system proxy settings.
    case system
    /// Connects directly, ignoring every configured proxy.
    case direct
  }

  /// Authentication challenge handling for a request.
  package enum ChallengePolicy: Sendable {
    /// Evaluates TLS server trust normally and cancels credential challenges.
    case serverTrustOnly
    /// Cancels every challenge.
    case rejectAll
  }

  /// A response status and its bounded body.
  package struct Response: Sendable {
    /// HTTP response status.
    package let status: Int
    /// Response bytes, never larger than the policy limit.
    package let body: Data
  }
}

private final class RedirectRefusingDelegate: NSObject, URLSessionTaskDelegate, Sendable {
  private let challenges: BoundedHTTPClient.ChallengePolicy

  init(challenges: BoundedHTTPClient.ChallengePolicy) { self.challenges = challenges }

  func urlSession(
    _: URLSession,
    task _: URLSessionTask,
    willPerformHTTPRedirection _: HTTPURLResponse,
    newRequest _: URLRequest,
    completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) { completionHandler(nil) }

  func urlSession(
    _: URLSession,
    task _: URLSessionTask,
    didReceive challenge: URLAuthenticationChallenge,
    completionHandler:
      @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
  ) {
    let serverTrust =
      challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust
    completionHandler(
      challenges == .serverTrustOnly && serverTrust
        ? .performDefaultHandling : .cancelAuthenticationChallenge,
      nil
    )
  }
}
