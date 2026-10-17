import Foundation
import Synchronization

private final class ReplyLatch<Value: Sendable>: Sendable {
  private let continuation: Mutex<CheckedContinuation<Value, Never>?>

  init(_ continuation: CheckedContinuation<Value, Never>) {
    self.continuation = Mutex(continuation)
  }

  func finish(_ value: Value) {
    continuation.withLock { continuation in
      continuation?.resume(returning: value)
      continuation = nil
    }
  }
}

struct WorkerObservation: Sendable {
  var result: DocumentResult
  var processID: Int32
  var terminated: Bool
  var elapsedSec: TimeInterval
}

actor DocumentWorkerClient {
  private var active = false

  func inspect(_ bytes: Data, serviceRequirement: String? = nil, exercise: Bool = false) async
    -> WorkerObservation
  {
    let start = Date()
    guard bytes.count <= DocumentWorkerLimits.inputBytes else {
      return .init(
        result: .init(status: .inputLimit),
        processID: 0,
        terminated: true,
        elapsedSec: 0
      )
    }
    guard !active else {
      return .init(result: .init(status: .busy), processID: 0, terminated: true, elapsedSec: 0)
    }
    active = true
    defer { active = false }
    let connection = NSXPCConnection(serviceName: DocumentWorkerIdentity.service)
    connection.remoteObjectInterface = NSXPCInterface(with: DocumentWorkerProtocol.self)
    connection.setCodeSigningRequirement(
      serviceRequirement
        ?? DocumentWorkerIdentity.requirement(identifier: DocumentWorkerIdentity.service)
    )
    let (closed, signalClosed) = AsyncStream<Void>.makeStream()
    connection.interruptionHandler = {
      signalClosed.yield(()); signalClosed.finish()
    }
    connection.invalidationHandler = {
      signalClosed.yield(()); signalClosed.finish()
    }
    connection.activate()
    defer { connection.invalidate(); signalClosed.finish() }
    let processID = await identify(connection)
    guard processID > 0, processID == connection.processIdentifier else {
      return .init(
        result: .init(status: .unavailable),
        processID: 0,
        terminated: true,
        elapsedSec: Date().timeIntervalSince(start)
      )
    }
    let result = await exchange(bytes, connection: connection, exercise: exercise)
    if result.status != .unavailable, result.status != .deadline, result.status != .busy,
      let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in })
        as? any DocumentWorkerProtocol
    {
      proxy.terminate()
    }
    let terminated = await withTaskGroup(of: Bool.self) { group in
      group.addTask {
        for await _ in closed { return true }
        return true
      }
      group.addTask {
        try? await Task.sleep(for: .seconds(1))
        return false
      }
      let result = await group.next() ?? false
      group.cancelAll()
      return result
    }
    return .init(
      result: result,
      processID: processID,
      terminated: terminated,
      elapsedSec: Date().timeIntervalSince(start)
    )
  }

  private func identify(_ connection: NSXPCConnection) async -> Int32 {
    await withCheckedContinuation { continuation in
      let latch = ReplyLatch(continuation)
      guard
        let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in latch.finish(0) })
          as? any DocumentWorkerProtocol
      else {
        latch.finish(0)
        return
      }
      proxy.identity { latch.finish($0) }
      DispatchQueue.global().asyncAfter(
        deadline: .now() + DocumentWorkerLimits.connectionDeadlineSec
      ) {
        latch.finish(0)
      }
    }
  }

  private func exchange(_ bytes: Data, connection: NSXPCConnection, exercise: Bool) async
    -> DocumentResult
  {
    await withCheckedContinuation { continuation in
      let latch = ReplyLatch(continuation)
      guard
        let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
          latch.finish(.init(status: .unavailable))
        }) as? any DocumentWorkerProtocol
      else {
        latch.finish(.init(status: .unavailable))
        return
      }
      let reply: @Sendable (Data) -> Void = { data in
        guard data.count <= DocumentWorkerLimits.outputBytes,
          let result = try? JSONDecoder().decode(DocumentResult.self, from: data),
          result.text.count <= DocumentWorkerLimits.textCharacters,
          result.status == .extracted || result.text.isEmpty
        else { latch.finish(.init(status: .invalidReply)); return }
        latch.finish(result)
      }
      #if DOCUMENT_WORKER_PROBE
        if exercise {
          proxy.exercise(bytes, withReply: reply)
        } else {
          proxy.inspectPDF(bytes, withReply: reply)
        }
      #else
        proxy.inspectPDF(bytes, withReply: reply)
      #endif
      DispatchQueue.global().asyncAfter(deadline: .now() + DocumentWorkerLimits.requestDeadlineSec)
      {
        latch.finish(.init(status: .deadline))
      }
    }
  }
}
