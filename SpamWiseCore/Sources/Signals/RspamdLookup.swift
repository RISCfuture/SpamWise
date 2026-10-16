public import Foundation

/// Optional local Rspamd scan; absent executables, sandbox denial and malformed output remain unknown.
public struct RspamdLookup: Sendable {
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
    guard raw.count <= 2_000_000, executablePath.hasPrefix("/"),
      URL(fileURLWithPath: executablePath).lastPathComponent == "rspamc"
    else { return unknown }
    do {
      let data = try await process.run(
        executable: executablePath,
        arguments: ["--json", "--connect=127.0.0.1:11333", "--timeout=2", "symbols"],
        input: raw
      )
      guard data.count <= 65_536 else { return unknown }
      let response = try JSONDecoder().decode(Response.self, from: data)
      guard response.symbols.count <= 200,
        response.symbols.allSatisfy({
          $0.key.utf8.count <= 80
            && $0.key.utf8.allSatisfy {
              (65...90).contains($0) || (48...57).contains($0) || $0 == 95
            }
            && $0.value.score.isFinite && abs($0.value.score) <= 10_000
        })
      else { return unknown }
      let details = response.symbols.sorted { $0.key < $1.key }.prefix(20).map {
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
