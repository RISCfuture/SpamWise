import Darwin
import Foundation

@main private enum DocumentProbeHost {
  static func main() async {
    do {
      try await run()
    } catch {
      print("FAIL: \(error)")
      exit(1)
    }
  }

  private static func run() async throws {
    let client = DocumentWorkerClient()
    if CommandLine.arguments.contains("--unauthorized") {
      let observation = await client.inspect(DocumentFixtures.pdf())
      try verify("unauthorized-caller", observation, expected: .unavailable, processExpected: false)
      return
    }
    if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--access",
      let port = UInt16(CommandLine.arguments[3])
    {
      try await inspectAccess(client, path: CommandLine.arguments[2], port: port)
      return
    }
    let plain = DocumentFixtures.pdf()
    try verify(
      "ordinary",
      await client.inspect(plain),
      expected: .extracted,
      text: "Synthetic offer"
    )
    if CommandLine.arguments.contains("--smoke") { return }
    try await inspectLifecycle(client)
    try await inspectDocuments(client)
    try await inspectFailures(client)
    print("PASS: document worker harness")
  }

  private static func inspectLifecycle(_ client: DocumentWorkerClient) async throws {
    let cancelled = Task {
      unsafe withUnsafeCurrentTask { unsafe $0?.cancel() }
      return await client.inspect(DocumentFixtures.pdf())
    }
    try verify(
      "immediate-cancellation",
      await cancelled.value,
      expected: .cancelled,
      processExpected: false
    )
    try await inspectCompletionRaces()
    let command = try JSONEncoder().encode(ProbeCommand(operation: "hang"))
    let pending = Task { await client.inspect(command, exercise: true) }
    let readyDeadline = ContinuousClock.now.advanced(by: .seconds(13))
    while await client.requestProcessID == 0, ContinuousClock.now < readyDeadline {
      try await Task.sleep(for: .milliseconds(10))
    }
    guard await client.requestProcessID > 0 else {
      pending.cancel()
      _ = await pending.value
      throw ProbeError.failed("in-flight-request-not-started")
    }
    try verify(
      "concurrent-request-is-busy",
      await client.inspect(DocumentFixtures.pdf()),
      expected: .busy,
      processExpected: false
    )
    let start = ContinuousClock.now
    pending.cancel()
    let result = await pending.value
    try verify("in-flight-cancellation", result, expected: .cancelled)
    let cancellationLatency = start.duration(to: .now)
    print("cancellation-latency: \(cancellationLatency)")
    guard cancellationLatency < .seconds(1) else {
      throw ProbeError.failed("cancellation-waited-for-watchdog")
    }
    print("cancelled-worker-pid: \(result.processID)")
    let recovered = await client.inspect(DocumentFixtures.pdf())
    try verify(
      "recovery-after-cancellation",
      recovered,
      expected: .extracted,
      text: "Synthetic offer"
    )
    guard recovered.processID != result.processID else {
      throw ProbeError.failed("cancelled-worker-was-reused")
    }
  }

  private static func inspectCompletionRaces() async throws {
    let beforeInstall = ReplyLatch<Int>()
    beforeInstall.finish(1)
    beforeInstall.finish(2)
    let early = await withCheckedContinuation { beforeInstall.install($0) }
    guard early == 1 else { throw ProbeError.failed("cancellation-before-continuation") }
    let pending = ReplyLatch<Int>()
    let result = await withCheckedContinuation { continuation in
      pending.install(continuation)
      pending.finish(3)
      pending.finish(4)
    }
    try await Task.sleep(for: .milliseconds(10))
    pending.finish(5)
    guard result == 3 else { throw ProbeError.failed("duplicate-or-late-completion") }
    print("PASS: completion-before-install, duplicate-completion, late-completion")
  }

  private static func inspectAccess(_ client: DocumentWorkerClient, path: String, port: UInt16)
    async throws
  {
    let marker = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try Data("Synthetic host-container marker".utf8).write(to: marker)
    defer { try? FileManager.default.removeItem(at: marker) }
    for (name, location) in [("outside-container", path), ("host-container", marker.path)] {
      let command = try JSONEncoder().encode(
        ProbeCommand(operation: "access", path: location, port: port)
      )
      try verify(
        name,
        await client.inspect(command, exercise: true),
        expected: .extracted,
        text: "network=1,file=1"
      )
    }
  }

  private static func inspectDocuments(_ client: DocumentWorkerClient) async throws {
    try verify(
      "active-content",
      await client.inspect(DocumentFixtures.pdf(active: true)),
      expected: .extracted,
      text: "Synthetic offer"
    )
    try verify(
      "encrypted",
      await client.inspect(DocumentFixtures.encrypted(password: "synthetic")),
      expected: .encrypted
    )
    try verify(
      "owner-encrypted",
      await client.inspect(DocumentFixtures.encrypted(password: "")),
      expected: .encrypted
    )
    try verify(
      "malformed",
      await client.inspect(Data("%PDF-1.7\nbroken".utf8)),
      expected: .malformed
    )
    try verify(
      "oversized-input",
      await client.inspect(Data(repeating: 0, count: DocumentWorkerLimits.inputBytes + 1)),
      expected: .inputLimit,
      processExpected: false
    )
    try verify(
      "page-limit",
      await client.inspect(DocumentFixtures.pdf(pages: 13)),
      expected: .pageLimit
    )
    try verify(
      "text-limit",
      await client.inspect(DocumentFixtures.pdf(text: String(repeating: "x", count: 3100))),
      expected: .extracted,
      text: String(repeating: "x", count: 3000)
    )
  }

  private static func inspectFailures(_ client: DocumentWorkerClient) async throws {
    let plain = DocumentFixtures.pdf()
    let wrong = DocumentWorkerIdentity.requirement(identifier: "codes.tim.SpamWise.NotTheWorker")
    try verify(
      "wrong-service-identity",
      await client.inspect(plain, serviceRequirement: wrong),
      expected: .unavailable,
      processExpected: false
    )
    for operation in ["hang", "crash", "cpu", "memory"] {
      let command = try JSONEncoder().encode(ProbeCommand(operation: operation))
      try verify(operation, await client.inspect(command, exercise: true), expected: .unavailable)
      try verify(
        "recovery-after-\(operation)",
        await client.inspect(plain),
        expected: .extracted,
        text: "Synthetic offer"
      )
    }
    for operation in ["invalid-reply", "oversized-text"] {
      let command = try JSONEncoder().encode(ProbeCommand(operation: operation))
      try verify(operation, await client.inspect(command, exercise: true), expected: .invalidReply)
    }
    let resourceCommand = try JSONEncoder().encode(ProbeCommand(operation: "rlimit"))
    try verify(
      "rlimit-not-a-memory-cap",
      await client.inspect(resourceCommand, exercise: true),
      expected: .extracted,
      text: "result=-1,errno=22"
    )
  }

  private static func verify(
    _ name: String,
    _ observation: WorkerObservation,
    expected: DocumentResult.Status,
    text: String = "",
    processExpected: Bool = true
  ) throws {
    print(
      "\(name): \(observation.result.status.rawValue), pid=\(observation.processID), closed=\(observation.connectionClosed), characters=\(observation.result.text.count), seconds=\(observation.elapsedSec)"
    )
    if !observation.result.text.isEmpty, observation.result.text.count < 100 {
      print("synthetic-result: \(observation.result.text)")
    }
    guard observation.result == DocumentResult(status: expected, text: text),
      observation.connectionClosed,
      !processExpected || observation.processID > 0
    else { throw ProbeError.failed(name) }
  }
}
