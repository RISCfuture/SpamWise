public import Foundation
import MessageModel

/**
 Optional scan by the user's Rspamd service on the IPv4 loopback interface; an absent service,
 sandbox denial and malformed output remain unknown.
 */
public struct RspamdLookup: Sendable {
  /// Longest time a scan may take, even when the caller allows more.
  public static let maximumScanTime = Duration.seconds(3)
  /// The fixed loopback address of the scanner's HTTP interface.
  public static let endpoint = URL(string: "http://127.0.0.1:11333/checkv2")!
  private static let maximumResponseBytes = 65_536
  private static let maximumAbsoluteScore: Double = 10_000
  private static let maximumSymbols = 200
  private static let maximumSymbolBytes = 80
  private static let maximumDetails = 20
  private static let symbolLetters = UInt8(ascii: "A")...UInt8(ascii: "Z")
  private static let symbolDigits = UInt8(ascii: "0")...UInt8(ascii: "9")
  private static let symbolSeparator = UInt8(ascii: "_")
  private let client: BoundedHTTPClient

  /// Scans through the fixed loopback endpoint.
  public init() { self.init(configuration: { .ephemeral }) }

  /// Scans through sessions built by `configuration`, such as a test fixture's, under the same bounds.
  package init(configuration: @escaping @Sendable () -> URLSessionConfiguration) {
    client = BoundedHTTPClient(
      policy: .init(
        maximumResponseBytes: Self.maximumResponseBytes,
        timeout: Self.maximumScanTime,
        proxies: .direct,
        challenges: .rejectAll
      ),
      configuration: configuration
    )
  }

  private static func request(raw: Data) -> URLRequest {
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.httpBody = raw
    request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
    return request
  }

  private static func isValid(_ symbol: (key: String, value: Response.Symbol)) -> Bool {
    symbol.key.utf8.count <= maximumSymbolBytes
      && symbol.key.utf8.allSatisfy {
        symbolLetters.contains($0) || symbolDigits.contains($0) || $0 == symbolSeparator
      }
      && symbol.value.score.isFinite && abs(symbol.value.score) <= maximumAbsoluteScore
  }

  /// Reports symbols without applying actions, within the caller's budget or ``maximumScanTime``.
  public func lookup(raw: Data, timeout: TimeInterval? = nil) async -> ExternalEvidenceFinding {
    let unknown = ExternalEvidenceFinding(
      source: .localRspamd,
      subject: "message",
      status: .unknown
    )
    let limit = Self.maximumScanTime / .seconds(1), timeout = timeout ?? limit
    guard raw.count <= MIMEParser.maximumMessageBytes, timeout.isFinite, timeout > 0 else {
      return unknown
    }
    do {
      let data = try await client.send(
        Self.request(raw: raw),
        timeout: .seconds(min(timeout, limit))
      )
      .body
      let response = try JSONDecoder().decode(Response.self, from: data)
      guard response.symbols.count <= Self.maximumSymbols, response.symbols.allSatisfy(Self.isValid)
      else { return unknown }
      let details = response.symbols.sorted { $0.key < $1.key }.prefix(Self.maximumDetails).map {
        "\($0.key): \($0.value.score)"
      }
      return .init(source: .localRspamd, subject: "message", status: .observed, details: details)
    } catch { return unknown }
  }

  private struct Response: Decodable {
    var symbols: [String: Symbol]

    struct Symbol: Decodable { var score: Double }
  }
}
