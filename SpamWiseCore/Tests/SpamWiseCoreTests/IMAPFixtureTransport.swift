import Foundation
import MailIntegration

actor IMAPFixtureTransport: IMAPTransport {
  private var bytes: Data
  private let fragment: Int
  var commands: [String] = []
  init(response: String, fragment: Int = 65_536) {
    bytes = Data(response.utf8); self.fragment = fragment
  }
  func connect() async throws {}
  func send(_ data: Data) async throws { commands.append(String(decoding: data, as: UTF8.self)) }
  func receive() async throws -> Data {
    let next = Data(bytes.prefix(fragment)); bytes.removeFirst(next.count); return next
  }
  func close() async {}
}
