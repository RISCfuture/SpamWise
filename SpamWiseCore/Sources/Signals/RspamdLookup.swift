public import Foundation

/// Optional local Rspamd scan; absent executables, sandbox denial and malformed output remain unknown.
public struct RspamdLookup: Sendable {
  private static let maximumMessageBytes = 2_000_000
  private static let maximumOutputBytes = 65_536
  private static let maximumAbsoluteScore: Double = 10_000
  private static let maximumSymbols = 200
  private static let maximumSymbolBytes = 80
  private static let maximumDetails = 20
  private let executablePath: String
  private let process: EvidenceProcess

  /// Selects a local rspamc executable; the daemon endpoint is restricted to IPv4 loopback.
  public init(executablePath: String, process: EvidenceProcess = .live) {
    self.executablePath = executablePath; self.process = process
  }

  /// Supplies bounded raw mail through stdin and reports symbols without applying Rspamd's action.
  public func lookup(raw: Data) async -> ExternalEvidenceFinding {
    let unknown = ExternalEvidenceFinding(
      source: "Local Rspamd",
      subject: "message",
      status: .unknown
    )
    guard raw.count <= Self.maximumMessageBytes, executablePath.hasPrefix("/"),
      URL(fileURLWithPath: executablePath).lastPathComponent == "rspamc"
    else { return unknown }
    do {
      let data = try await process.run(
        executable: executablePath,
        arguments: ["--json", "--connect=127.0.0.1:11333", "--timeout=2", "symbols"],
        input: raw
      )
      guard data.count <= Self.maximumOutputBytes else { return unknown }
      let response = try JSONDecoder().decode(Response.self, from: data)
      guard response.symbols.count <= Self.maximumSymbols,
        response.symbols.allSatisfy({
          $0.key.utf8.count <= Self.maximumSymbolBytes
            && $0.key.utf8.allSatisfy {
              (65...90).contains($0) || (48...57).contains($0) || $0 == 95
            }
            && $0.value.score.isFinite && abs($0.value.score) <= Self.maximumAbsoluteScore
        })
      else { return unknown }
      let details = response.symbols.sorted { $0.key < $1.key }.prefix(Self.maximumDetails).map {
        "\($0.key): \($0.value.score)"
      }
      return .init(source: "Local Rspamd", subject: "message", status: .observed, details: details)
    } catch { return unknown }
  }

  private struct Response: Decodable {
    var symbols: [String: Symbol]
    struct Symbol: Decodable { var score: Double }
  }
}
