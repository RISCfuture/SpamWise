import Foundation
import MessageModel

enum SpamhausHTTPS {
  private static let maximumResponseBytes = 16_384
  private static let maximumCodes = 20
  private static let maximumKeyBytes = 256
  private static let codes: [Int: String] = [
    2002: "127.0.1.2", 2004: "127.0.1.4", 2005: "127.0.1.5",
    2006: "127.0.1.6", 2102: "127.0.1.102", 2103: "127.0.1.103", 2104: "127.0.1.104",
    2105: "127.0.1.105", 2106: "127.0.1.106"
  ]

  static func request(domain: String, key: String) throws -> URLRequest {
    guard !key.isEmpty, key.utf8.count <= maximumKeyBytes,
      key.utf8.allSatisfy({ (33...126).contains($0) }),
      let endpoint = URL(string: "https://apibl.spamhaus.net/lookup/v1/DBL/" + domain)
    else { throw URLError(.userAuthenticationRequired) }
    var request = URLRequest(url: endpoint)
    request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
    return request
  }

  static func answer(status: Int, data: Data) -> SpamhausDomainLookup.DNSAnswer {
    let unknown = SpamhausDomainLookup.DNSAnswer(status: .failed, addresses: [])
    guard data.count <= maximumResponseBytes,
      let body = try? JSONDecoder().decode(Response.self, from: data), body.status == status
    else { return unknown }
    if status == 404, body.resp == nil { return .init(status: .notFound, addresses: []) }
    guard status == 200, let values = body.resp, !values.isEmpty, values.count <= maximumCodes,
      values.allSatisfy({ codes[$0] != nil })
    else { return unknown }
    return .init(status: .answered, addresses: values.compactMap { codes[$0] })
  }

  static func query(
    domain: String,
    key: String,
    timeout: TimeInterval,
    configuration: URLSessionConfiguration = .ephemeral
  )
    async throws -> SpamhausDomainLookup.DNSAnswer
  {
    let request = try request(domain: domain, key: key)
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.urlCredentialStorage = nil
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.timeoutIntervalForRequest = timeout
    configuration.timeoutIntervalForResource = timeout
    configuration.waitsForConnectivity = false
    let session = URLSession(configuration: configuration, delegate: Delegate(), delegateQueue: nil)
    defer { session.invalidateAndCancel() }
    return try await withTaskCancellationHandler {
      try await withResourceDeadline(seconds: timeout) {
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, response.url == request.url,
          [200, 404].contains(response.statusCode),
          response.mimeType?.lowercased() == "application/json",
          response.expectedContentLength <= maximumResponseBytes
        else { throw URLError(.badServerResponse) }
        var data = Data()
        for try await byte in bytes {
          try Task.checkCancellation()
          guard data.count < maximumResponseBytes else { throw URLError(.dataLengthExceedsMaximum) }
          data.append(byte)
        }
        return answer(status: response.statusCode, data: data)
      }
    } onCancel: {
      session.invalidateAndCancel()
    }
  }

  private struct Response: Decodable {
    let status: Int
    let resp: [Int]?
  }

  private final class Delegate: NSObject, URLSessionTaskDelegate, Sendable {
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
      completionHandler(
        challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust
          ? .performDefaultHandling : .cancelAuthenticationChallenge,
        nil
      )
    }
  }
}
