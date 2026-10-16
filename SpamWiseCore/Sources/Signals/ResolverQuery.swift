import CResolver
import Darwin
import Foundation

/// In-process DNS A-record queries sent only to one explicitly configured IPv4 resolver.
enum ResolverQuery {
  private static let standardPort: UInt16 = 53
  private static let retransmissionInterval = Duration.seconds(2)
  private static let attempts: Int32 = 1
  private static let maximumResponseBytes = 4096
  private static let addressRecordBytes = 4

  /// Parses a decimal dotted-quad IPv4 address, rejecting host names and shorthand forms.
  static func address(_ text: String) -> in_addr? {
    var address = in_addr()
    return unsafe inet_pton(AF_INET, text, &address) == 1 ? address : nil
  }

  /// Queries an absolute name without search domains; resolver and transport failures are `.failed`.
  static func addresses(
    of name: String,
    resolver: String,
    port: UInt16 = standardPort
  ) async -> SpamhausDomainLookup.DNSAnswer {
    guard let server = address(resolver) else { return .init(status: .failed, addresses: []) }
    return await withCheckedContinuation { continuation in
      DispatchQueue.global(qos: .utility).async {
        continuation.resume(returning: query(name: name, server: server, port: port))
      }
    }
  }

  private static func query(name: String, server: in_addr, port: UInt16)
    -> SpamhausDomainLookup.DNSAnswer
  {
    var state: __res_9_state = unsafe .init()
    guard unsafe res_9_ninit(&state) == 0 else { return .init(status: .failed, addresses: []) }
    defer { unsafe res_9_ndestroy(&state) }
    var servers = res_9_sockaddr_union()
    unsafe servers.sin = sockaddr_in(
      sin_len: UInt8(MemoryLayout<sockaddr_in>.size),
      sin_family: sa_family_t(AF_INET),
      sin_port: port.bigEndian,
      sin_addr: server,
      sin_zero: (0, 0, 0, 0, 0, 0, 0, 0)
    )
    unsafe res_9_setservers(&state, &servers, 1)
    unsafe state.retrans = Int32(retransmissionInterval / .seconds(1))
    unsafe state.retry = attempts
    var response = [UInt8](repeating: 0, count: maximumResponseBytes)
    let length = unsafe res_9_nquery(
      &state,
      name,
      Int32(ns_c_in.rawValue),
      Int32(ns_t_a.rawValue),
      &response,
      Int32(response.count)
    )
    guard length >= 0 else { return failure(unsafe state.res_h_errno) }
    return answer(Array(response.prefix(Int(length))), name: name)
  }

  private static func failure(_ code: Int32) -> SpamhausDomainLookup.DNSAnswer {
    switch code {
      case HOST_NOT_FOUND: .init(status: .notFound, addresses: [])
      case NO_DATA: .init(status: .answered, addresses: [])
      default: .init(status: .failed, addresses: [])
    }
  }

  private static func answer(_ response: [UInt8], name: String) -> SpamhausDomainLookup.DNSAnswer {
    var message = unsafe res_9_ns_msg()
    guard unsafe res_9_ns_initparse(response, Int32(response.count), &message) == 0 else {
      return .init(status: .failed, addresses: [])
    }
    var addresses: [String] = []
    for index in 0..<Int32(unsafe message._counts.1) {
      var record = unsafe res_9_ns_rr()
      guard unsafe res_9_ns_parserr(&message, ns_s_an, index, &record) == 0 else {
        return .init(status: .failed, addresses: [])
      }
      guard unsafe isAddress(record, for: name) else { continue }
      guard let text = unsafe presentation(of: record.rdata) else {
        return .init(status: .failed, addresses: [])
      }
      addresses.append(text)
    }
    return .init(status: .answered, addresses: addresses)
  }

  private static func isAddress(_ record: res_9_ns_rr, for name: String) -> Bool {
    let owner = unsafe withUnsafeBytes(of: record.name) {
      unsafe String(bytes: $0.prefix { $0 != 0 }, encoding: .utf8)
    }
    guard let owner else { return false }
    return unsafe record.type == UInt16(ns_t_a.rawValue)
      && record.rr_class == UInt16(ns_c_in.rawValue)
      && Int(record.rdlength) == addressRecordBytes
      && owner.caseInsensitiveCompare(name) == .orderedSame
  }

  private static func presentation(of rdata: UnsafePointer<UInt8>?) -> String? {
    var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
    guard unsafe inet_ntop(AF_INET, rdata, &text, socklen_t(text.count)) != nil else {
      return nil
    }
    return String(bytes: text.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, encoding: .utf8)
  }
}
