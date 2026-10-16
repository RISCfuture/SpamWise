import Foundation
import Network

@main private enum RspamdHTTPFixture {
  private static let queue = DispatchQueue(label: "codes.tim.SpamWise.HTTPFixture")
  private static let maximumRequestBytes = 2_010_000

  static func main() async throws {
    let scanner = try listen(port: 11333, trap: false)
    let redirectTrap = try listen(port: 11334, trap: true)
    defer { scanner.cancel(); redirectTrap.cancel() }
    try await Task.sleep(for: .seconds(120))
  }

  private static func listen(port: UInt16, trap: Bool) throws -> NWListener {
    let parameters = NWParameters.tcp
    parameters.allowLocalEndpointReuse = true
    parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .init(rawValue: port)!)
    let listener = try NWListener(using: parameters)
    listener.stateUpdateHandler = { state in
      if case .ready = state { log("ready \(port)") }
      if case .failed(let error) = state { log("failed \(port): \(error)") }
    }
    listener.newConnectionHandler = { connection in
      connection.start(queue: queue)
      receive(connection, accumulated: Data(), trap: trap)
    }
    listener.start(queue: queue)
    return listener
  }

  private static func receive(_ connection: NWConnection, accumulated: Data, trap: Bool) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, done, error in
      guard error == nil, let data, !data.isEmpty else { connection.cancel(); return }
      if trap { log("redirect-received"); connection.cancel(); return }
      var accumulated = accumulated
      accumulated.append(data)
      guard accumulated.count <= maximumRequestBytes else { connection.cancel(); return }
      if let divider = accumulated.range(of: Data("\r\n\r\n".utf8)) {
        let header = String(decoding: accumulated[..<divider.lowerBound], as: UTF8.self)
        let length = header.components(separatedBy: "\r\n").first {
          $0.lowercased().hasPrefix("content-length:")
        }.flatMap {
          Int($0.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces))
        }
        if let length, accumulated.count - divider.upperBound >= length {
          guard header.hasPrefix("POST /checkv2 HTTP/1.1"),
            !header.lowercased().contains("authorization:"),
            !header.lowercased().contains("cookie:")
          else { log("invalid-request"); connection.cancel(); return }
          respond(
            connection,
            body: String(decoding: accumulated[divider.upperBound...], as: UTF8.self)
          )
          return
        }
      }
      guard !done else { connection.cancel(); return }
      receive(connection, accumulated: accumulated, trap: false)
    }
  }

  private static func respond(_ connection: NWConnection, body: String) {
    if body.contains("redirect-probe") {
      log("redirect-sent")
      send(
        connection,
        "HTTP/1.1 307 Temporary Redirect\r\nLocation: http://127.0.0.1:11334/leak\r\nContent-Length: 0\r\n\r\n"
      )
    } else if body.contains("overflow-probe") {
      log("overflow-sent")
      send(
        connection,
        "HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n" + String(repeating: "x", count: 65_537)
      )
    } else if body.contains("timeout-probe") || body.contains("cancel-probe") {
      log(body.contains("cancel-probe") ? "cancel-started" : "timeout-started")
      connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { _, _, _, _ in
        log(body.contains("cancel-probe") ? "cancel-closed" : "timeout-closed")
        connection.cancel()
      }
    } else if body.contains("failure-probe") {
      log("failure-sent")
      send(
        connection,
        "HTTP/1.1 503 Service Unavailable\r\nContent-Length: 14\r\n\r\n{\"symbols\":{}}"
      )
    } else {
      let result =
        body.contains("spamwiseprobe")
        ? #"{"symbols":{"SPAMWISE_PROBE":{"score":1.5}}}"# : #"{"symbols":{}}"#
      log(body.contains("spamwiseprobe") ? "marker-sent" : "ordinary-sent")
      send(connection, "HTTP/1.1 200 OK\r\nContent-Length: \(result.utf8.count)\r\n\r\n" + result)
    }
  }

  private static func send(_ connection: NWConnection, _ response: String) {
    connection.send(
      content: Data(response.utf8),
      completion: .contentProcessed { _ in connection.cancel() }
    )
  }

  private static func log(_ message: String) {
    FileHandle.standardOutput.write(Data((message + "\n").utf8))
  }
}
