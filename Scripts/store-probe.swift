import Foundation

@main struct StoreProcessProbe {
  private static let maximumIncrements = 1000
  static func main() async throws {
    let arguments = CommandLine.arguments
    guard arguments.count == 3 else { throw StoreError.invalidPath }
    let store = try Store(url: URL(filePath: arguments[1]))
    if arguments[2] == "read" {
      print(try await store.read("concurrent-counter", default: 0))
      return
    }
    guard let count = Int(arguments[2]), (0...maximumIncrements).contains(count) else {
      throw StoreError.invalidPath
    }
    for _ in 0..<count {
      try await store.update("concurrent-counter", default: 0) { $0 += 1 }
    }
  }
}
