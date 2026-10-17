import Foundation
import MessageModel

enum RspamdLoopbackHTTP {
  private static let maximumResponseBytes = 65_536
  private static let timeoutSec: TimeInterval = 3

  static func configuration() -> URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.connectionProxyDictionary = [
      "HTTPEnable": 0, "HTTPSEnable": 0, "SOCKSEnable": 0,
      "ProxyAutoConfigEnable": 0, "ProxyAutoDiscoveryEnable": 0
    ]
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.urlCredentialStorage = nil
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.timeoutIntervalForRequest = timeoutSec
    configuration.timeoutIntervalForResource = timeoutSec
    configuration.waitsForConnectivity = false
    return configuration
  }

  static func scan(_ raw: Data, timeout: TimeInterval)
    async throws
    -> Data
  {
    guard let endpoint = URL(string: "http://127.0.0.1:11333/checkv2") else {
      throw URLError(.badURL)
    }
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.httpBody = raw
    request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
    let configuration = configuration()
    configuration.timeoutIntervalForRequest = timeout
    configuration.timeoutIntervalForResource = timeout
    let session = URLSession(
      configuration: configuration,
      delegate: ScanDelegate(),
      delegateQueue: nil
    )
    defer { session.invalidateAndCancel() }
    let fixedRequest = request
    return try await withTaskCancellationHandler {
      try await withResourceDeadline(seconds: timeout) {
        let (bytes, response) = try await session.bytes(for: fixedRequest)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
          response.url == endpoint, response.expectedContentLength <= maximumResponseBytes
        else { throw URLError(.badServerResponse) }
        var data = Data()
        for try await byte in bytes {
          try Task.checkCancellation()
          guard data.count < maximumResponseBytes else { throw URLError(.dataLengthExceedsMaximum) }
          data.append(byte)
        }
        return data
      }
    } onCancel: {
      session.invalidateAndCancel()
    }
  }

  private final class ScanDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
      _ session: URLSession,
      task: URLSessionTask,
      willPerformHTTPRedirection response: HTTPURLResponse,
      newRequest request: URLRequest,
      completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) { completionHandler(nil) }

    func urlSession(
      _ session: URLSession,
      task: URLSessionTask,
      didReceive challenge: URLAuthenticationChallenge,
      completionHandler:
        @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
      completionHandler(.cancelAuthenticationChallenge, nil)
    }
  }
}
