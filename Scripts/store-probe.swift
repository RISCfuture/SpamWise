import Foundation

@main struct StoreProcessProbe {
  static func main() async throws {
    let arguments = CommandLine.arguments
    guard arguments.count == 3 else { throw StoreError.invalidPath }
    let store = try Store(url: URL(filePath: arguments[1]))
    if arguments[2] == "read" {
      print(try await store.read("concurrent-counter", default: 0))
      return
    }
    guard let count = Int(arguments[2]), (0...1000).contains(count) else {
      throw StoreError.invalidPath
    }
    for _ in 0..<count { try await increment(store) }
  }
  private static func increment(_ store: Store) async throws {
    let deadline = ContinuousClock.now + .seconds(10)
    while ContinuousClock.now < deadline {
      do {
        try await store.update("concurrent-counter", default: 0) { $0 += 1 }
        return
      } catch StoreError.lockUnavailable {
        try await Task.sleep(for: .milliseconds(2))
      }
    }
    throw StoreError.lockUnavailable
  }
}
