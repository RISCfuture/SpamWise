import Foundation

enum DocumentWorkerLimits {
  static let inputBytes = 524_288
  static let outputBytes = 16_384
  static let pages = 12
  static let textCharacters = 3000
  static let connectionDeadlineSec = 12.0
  static let requestDeadlineSec = 4.0
  static let workerDeadlineSec = 3.0
  static let residentWatchdogBytes: UInt64 = 128 * 1024 * 1024
}

enum DocumentWorkerIdentity {
  static let service = "codes.tim.SpamWise.DocumentWorker"
  static let caller = "codes.tim.SpamWise.DocumentProbe"
  static let team = "2NFSK2WB24"

  static func requirement(identifier: String) -> String {
    "anchor apple generic and identifier \"\(identifier)\" "
      + "and certificate leaf[subject.OU] = \"\(team)\" "
      + "and entitlement[\"com.apple.security.app-sandbox\"] exists"
  }
}

struct DocumentResult: Codable, Sendable, Equatable {
  var status: Status
  var text = ""

  func encoded() -> Data {
    (try? JSONEncoder().encode(self)) ?? Data()
  }

  enum Status: String, Codable, Sendable {
    case extracted, encrypted, malformed, inputLimit, pageLimit, unreadable
    case unavailable, deadline, invalidReply, busy
  }
}

#if DOCUMENT_WORKER_PROBE
  struct ProbeCommand: Codable, Sendable {
    var operation: String
    var path: String?
    var port: UInt16?
  }
#endif

@objc protocol DocumentWorkerProtocol {
  func identity(withReply reply: @escaping @Sendable (Int32) -> Void)
  func inspectPDF(_ data: Data, withReply reply: @escaping @Sendable (Data) -> Void)
  func terminate()

  #if DOCUMENT_WORKER_PROBE
    func exercise(_ data: Data, withReply reply: @escaping @Sendable (Data) -> Void)
  #endif
}
