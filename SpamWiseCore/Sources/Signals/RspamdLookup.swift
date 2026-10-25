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
  private static let actions: Set<String> = [
    "no action", "greylist", "add header", "rewrite subject", "soft reject", "reject", "discard",
    "quarantine"
  ]
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
      && isValid(score: symbol.value.score)
  }

  private static func isValid(score: Double?) -> Bool {
    score.map { $0.isFinite && abs($0) <= maximumAbsoluteScore } ?? true
  }

  private static func isValid(_ response: Response) -> Bool {
    response.symbols.count <= maximumSymbols && response.symbols.allSatisfy(isValid)
      && isValid(score: response.score) && isValid(score: response.requiredScore)
      && (response.action.map(actions.contains) ?? true)
  }

  /// The scanner's overall action and scores, then symbols by descending weight and name.
  private static func details(_ response: Response) -> [String] {
    let verdict = [
      response.action.map { "action: \($0)" }, response.score.map { "score: \($0)" },
      response.requiredScore.map { "required score: \($0)" }
    ].compactMap(\.self)
    let symbols = response.symbols.sorted {
      abs($0.value.score) == abs($1.value.score)
        ? $0.key < $1.key : abs($0.value.score) > abs($1.value.score)
    }.map { "\($0.key): \($0.value.score)" }
    return Array(
      ((verdict.isEmpty ? [] : [verdict.joined(separator: ", ")]) + symbols)
        .prefix(maximumDetails)
    )
  }

  /**
   Reports the scanner's verdict and symbols without applying actions, within the caller's budget
   or ``maximumScanTime``.

   The first detail holds the overall action, score and required score the scanner reported,
   followed by the heaviest symbols.
   */
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
      guard Self.isValid(response) else { return unknown }
      return .init(
        source: .localRspamd,
        subject: "message",
        status: .observed,
        details: Self.details(response)
      )
    } catch { return unknown }
  }

  private struct Response: Decodable {
    var symbols: [String: Symbol]
    var score: Double?
    var requiredScore: Double?
    var action: String?

    struct Symbol: Decodable { var score: Double }

    private enum CodingKeys: String, CodingKey {
      case symbols, score, action
      case requiredScore = "required_score"
    }
  }
}
