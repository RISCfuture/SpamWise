import Darwin
import Foundation

enum WorkerProbes {
  static func exercise(_ data: Data) -> Data {
    guard let command = try? JSONDecoder().decode(ProbeCommand.self, from: data) else {
      return DocumentResult(status: .malformed).encoded()
    }
    switch command.operation {
      case "hang":
        Thread.sleep(forTimeInterval: 15)
      case "crash":
        _exit(42)
      case "cpu":
        while true { _ = getpid() }
      case "memory":
        var allocations: [Data] = []
        for _ in 0..<16 {
          allocations.append(Data(repeating: 0xA5, count: 16 * 1024 * 1024))
          Thread.sleep(forTimeInterval: 0.02)
        }
        withExtendedLifetime(allocations) { Thread.sleep(forTimeInterval: 2) }
      case "access":
        return access(command).encoded()
      case "rlimit":
        var limit = rlimit(rlim_cur: 16 * 1024 * 1024, rlim_max: 16 * 1024 * 1024)
        let result = unsafe setrlimit(RLIMIT_AS, &limit)
        return DocumentResult(status: .extracted, text: "result=\(result),errno=\(errno)").encoded()
      case "invalid-reply":
        return Data("invalid-json".utf8)
      case "oversized-text":
        return DocumentResult(status: .extracted, text: String(repeating: "x", count: 3001))
          .encoded()
      default: return DocumentResult(status: .malformed).encoded()
    }
    return DocumentResult(status: .extracted, text: "unexpected-completion").encoded()
  }

  private static func access(_ command: ProbeCommand) -> DocumentResult {
    guard let path = command.path, let port = command.port else { return .init(status: .malformed) }
    let descriptor = socket(AF_INET, SOCK_STREAM, 0)
    guard descriptor >= 0 else {
      return .init(status: .extracted, text: "socket=\(errno)")
    }
    defer { close(descriptor) }
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = port.bigEndian
    address.sin_addr.s_addr = unsafe inet_addr("127.0.0.1")
    let connected = withUnsafePointer(to: &address) { pointer in
      unsafe pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        unsafe connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    let networkError = connected == 0 ? 0 : errno
    let fileDescriptor = unsafe open(path, O_RDONLY)
    let fileError = fileDescriptor >= 0 ? 0 : errno
    if fileDescriptor >= 0 { close(fileDescriptor) }
    return .init(status: .extracted, text: "network=\(networkError),file=\(fileError)")
  }
}
