import Foundation
import Synchronization

final class ReplyLatch<Value: Sendable>: Sendable {
  private let state = Mutex(State())

  func install(_ continuation: CheckedContinuation<Value, Never>) {
    state.withLock { state in
      if let result = state.result {
        continuation.resume(returning: result)
      } else {
        state.continuation = continuation
      }
    }
  }

  func finish(_ value: Value) {
    state.withLock { state in
      guard state.result == nil else { return }
      state.result = value
      state.continuation?.resume(returning: value)
      state.continuation = nil
    }
  }

  private struct State: Sendable {
    var continuation: CheckedContinuation<Value, Never>?
    var result: Value?
  }
}

struct WorkerObservation: Sendable {
  var result: DocumentResult
  var processID: Int32
  var connectionClosed: Bool
  var elapsedSec: TimeInterval
}

actor DocumentWorkerClient {
  private var active = false
  private(set) var requestProcessID: Int32 = 0

  func inspect(_ bytes: Data, serviceRequirement: String? = nil, exercise: Bool = false) async
    -> WorkerObservation
  {
    let start = Date()
    guard !Task.isCancelled else {
      return .init(
        result: .init(status: .cancelled),
        processID: 0,
        connectionClosed: true,
        elapsedSec: 0
      )
    }
    guard bytes.count <= DocumentWorkerLimits.inputBytes else {
      return .init(
        result: .init(status: .inputLimit),
        processID: 0,
        connectionClosed: true,
        elapsedSec: 0
      )
    }
    guard !active else {
      return .init(
        result: .init(status: .busy),
        processID: 0,
        connectionClosed: true,
        elapsedSec: 0
      )
    }
    active = true
    defer { active = false; requestProcessID = 0 }
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
        result: .init(status: Task.isCancelled ? .cancelled : .unavailable),
        processID: 0,
        connectionClosed: true,
        elapsedSec: Date().timeIntervalSince(start)
      )
    }
    requestProcessID = processID
    let result = await exchange(bytes, connection: connection, exercise: exercise)
    if result.status == .cancelled { connection.invalidate() }
    if result.status != .unavailable, result.status != .deadline, result.status != .busy,
      result.status != .cancelled,
      let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in })
        as? any DocumentWorkerProtocol
    {
      proxy.terminate()
    }
    let connectionClosed = await waitForClosure(closed)
    return .init(
      result: result,
      processID: processID,
      connectionClosed: connectionClosed,
      elapsedSec: Date().timeIntervalSince(start)
    )
  }

  private func waitForClosure(_ closed: AsyncStream<Void>) async -> Bool {
    await Task.detached {
      await withTaskGroup(of: Bool.self) { group in
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
    }.value
  }

  private func identify(_ connection: NSXPCConnection) async -> Int32 {
    let latch = ReplyLatch<Int32>()
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        latch.install(continuation)
        guard !Task.isCancelled else { latch.finish(0); return }
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
    } onCancel: {
      latch.finish(0)
    }
  }

  private func exchange(_ bytes: Data, connection: NSXPCConnection, exercise: Bool) async
    -> DocumentResult
  {
    let latch = ReplyLatch<DocumentResult>()
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        latch.install(continuation)
        guard !Task.isCancelled else { latch.finish(.init(status: .cancelled)); return }
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
        DispatchQueue.global().asyncAfter(
          deadline: .now() + DocumentWorkerLimits.requestDeadlineSec
        ) {
          latch.finish(.init(status: .deadline))
        }
      }
    } onCancel: {
      latch.finish(.init(status: .cancelled))
    }
  }
}
