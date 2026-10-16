import Darwin
import Foundation
import OSLog
import Synchronization

enum WorkerResources {
  static func residentBytes() -> UInt64? {
    var usage = rusage_info_v2()
    let result = withUnsafeMutablePointer(to: &usage) { pointer in
      unsafe pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
        unsafe proc_pid_rusage(getpid(), RUSAGE_INFO_V2, $0)
      }
    }
    return result == 0 ? usage.ri_resident_size : nil
  }

  static func install() -> Bool {
    var cpu = rlimit(rlim_cur: 2, rlim_max: 2)
    var core = rlimit(rlim_cur: 0, rlim_max: 0)
    return unsafe setrlimit(RLIMIT_CPU, &cpu) == 0 && setrlimit(RLIMIT_CORE, &core) == 0
  }
}

final class DocumentWorker: NSObject, DocumentWorkerProtocol, Sendable {
  private static let active = Mutex(false)
  private static let logger = Logger(subsystem: DocumentWorkerIdentity.service, category: "limits")
  private let lifecycle = Mutex(Lifecycle.connected)

  func identity(withReply reply: @escaping @Sendable (Int32) -> Void) { reply(getpid()) }

  func inspectPDF(_ data: Data, withReply reply: @escaping @Sendable (Data) -> Void) {
    guard data.count <= DocumentWorkerLimits.inputBytes else {
      reply(DocumentResult(status: .inputLimit).encoded())
      return
    }
    run(reply: reply) { PDFExtraction.extract(data).encoded() }
  }

  func terminate() { _exit(0) }

  func connectionInvalidated() {
    lifecycle.withLock { lifecycle in
      if lifecycle == .running { _exit(76) }
      lifecycle = .disconnected
    }
  }

  private func run(
    reply: @escaping @Sendable (Data) -> Void,
    operation: @escaping @Sendable () -> Data
  ) {
    guard
      Self.active.withLock({ active in
        if active { return false }
        active = true
        return true
      })
    else {
      reply(DocumentResult(status: .busy).encoded())
      return
    }
    lifecycle.withLock { lifecycle in
      guard lifecycle == .connected else { _exit(76) }
      lifecycle = .running
    }
    let monitor = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
    let deadline = ProcessInfo.processInfo.systemUptime + DocumentWorkerLimits.workerDeadlineSec
    monitor.schedule(deadline: .now(), repeating: .milliseconds(10))
    monitor.setEventHandler {
      guard let resident = WorkerResources.residentBytes() else { _exit(72) }
      if resident > DocumentWorkerLimits.residentWatchdogBytes {
        Self.logger.error("Resident-memory watchdog termination: \(resident) bytes")
        _exit(73)
      }
      if ProcessInfo.processInfo.systemUptime >= deadline {
        Self.logger.error("Wall-clock watchdog termination")
        _exit(74)
      }
    }
    monitor.activate()
    DispatchQueue.global(qos: .userInitiated).async {
      let output = operation()
      guard output.count <= DocumentWorkerLimits.outputBytes else { _exit(75) }
      reply(output)
      withExtendedLifetime(monitor) {}
    }
  }

  #if DOCUMENT_WORKER_PROBE
    func exercise(_ data: Data, withReply reply: @escaping @Sendable (Data) -> Void) {
      guard data.count <= DocumentWorkerLimits.inputBytes else {
        reply(DocumentResult(status: .inputLimit).encoded())
        return
      }
      run(reply: reply) { WorkerProbes.exercise(data) }
    }
  #endif

  private enum Lifecycle { case connected, running, disconnected }
}

private final class WorkerListener: NSObject, NSXPCListenerDelegate {
  func listener(_: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection)
    -> Bool
  {
    guard connection.effectiveUserIdentifier == geteuid(), connection.processIdentifier > 0 else {
      return false
    }
    connection.setCodeSigningRequirement(
      DocumentWorkerIdentity.requirement(identifier: DocumentWorkerIdentity.caller)
    )
    connection.exportedInterface = NSXPCInterface(with: DocumentWorkerProtocol.self)
    let worker = DocumentWorker()
    connection.exportedObject = worker
    connection.invalidationHandler = { worker.connectionInvalidated() }
    connection.interruptionHandler = { worker.connectionInvalidated() }
    connection.activate()
    return true
  }
}

@main
private enum WorkerMain {
  static func main() {
    guard WorkerResources.install() else { _exit(71) }
    let listener = NSXPCListener.service(), delegate = WorkerListener()
    listener.delegate = delegate
    listener.resume()
    withExtendedLifetime(delegate) { dispatchMain() }
  }
}
