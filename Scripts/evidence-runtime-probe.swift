import AppKit
import Foundation
import SpamWiseCore

private enum ProbeFailure: Error {
  case fixture, unexpected(String), credentialRead
}

private struct Observation: Encodable {
  var name: String
  var result: String
  var text: String?
}

private struct ImageFixture {
  var name: String
  var text: String
  var type: NSBitmapImageRep.FileType
  var mime: String
  var disposition = "inline"
}

@main private struct EvidenceRuntimeProbe {
  private static let imageWidth = 1600
  private static let imageHeight = 240
  private static let observerDelay = Duration.seconds(4)

  static func main() async throws {
    let mode = CommandLine.arguments.dropFirst().first ?? "ocr"
    print("probe-pid: \(ProcessInfo.processInfo.processIdentifier)")
    try await Task.sleep(for: observerDelay)
    switch mode {
      case "ocr": try await inspectImages()
      case "privacy": try await inspectPrivacy()
      case "network-control": try await networkControl()
      case "rspamd": try await inspectRspamd()
      case "rspamd-http": try await inspectRspamdHTTP()
      case "rspamd-http-faults": try await inspectRspamdHTTPFaults()
      default: throw ProbeFailure.unexpected("Unknown mode")
    }
    try await Task.sleep(for: observerDelay)
  }

  private static func emit(_ name: String, result: String, text: String? = nil) throws {
    let data = try JSONEncoder().encode(Observation(name: name, result: result, text: text))
    print(String(decoding: data, as: UTF8.self))
  }

  @MainActor private static func raster(_ text: String, type: NSBitmapImageRep.FileType) throws
    -> Data
  {
    guard
      let bitmap = unsafe NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: imageWidth,
        pixelsHigh: imageHeight,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
      ), let context = NSGraphicsContext(bitmapImageRep: bitmap)
    else { throw ProbeFailure.fixture }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: imageWidth, height: imageHeight).fill()
    (text as NSString).draw(
      at: NSPoint(x: 32, y: 100),
      withAttributes: [.font: NSFont.systemFont(ofSize: 44), .foregroundColor: NSColor.black]
    )
    let properties: [NSBitmapImageRep.PropertyKey: Any] =
      type == .tiff ? [.compressionMethod: NSBitmapImageRep.TIFFCompression.lzw.rawValue] : [:]
    guard let data = bitmap.representation(using: type, properties: properties) else {
      throw ProbeFailure.fixture
    }
    return data
  }

  private static func message(image: Data, mime: String, disposition: String = "inline") -> Data {
    Data(
      """
      From: fixture@example.com
      To: reader@example.net
      Subject: Synthetic local evidence probe
      Message-ID: <evidence-runtime-probe@example.com>
      MIME-Version: 1.0
      Content-Type: multipart/related; boundary=probe-images

      --probe-images
      Content-Type: text/html

      <p>Synthetic fixture only.</p><img src="https://example.com/never-fetch.png">
      --probe-images
      Content-Type: \(mime)
      Content-Disposition: \(disposition)
      Content-Transfer-Encoding: base64

      \(image.base64EncodedString())
      --probe-images--

      """.utf8
    )
  }

  private static func inspectImages() async throws {
    let cases: [ImageFixture] = [
      .init(
        name: "english-png",
        text: "Your invoice total is 42 dollars",
        type: .png,
        mime: "image/png"
      ),
      .init(
        name: "spanish-jpeg",
        text: "Su factura total es de 42 euros",
        type: .jpeg,
        mime: "image/jpeg"
      ),
      .init(
        name: "french-png",
        text: "Votre facture est de 42 euros",
        type: .png,
        mime: "image/png"
      ),
      .init(
        name: "attached-png",
        text: "Attached invoice total is 42 dollars",
        type: .png,
        mime: "image/png",
        disposition: "attachment"
      ),
      .init(
        name: "static-gif",
        text: "Static image total is 42 dollars",
        type: .gif,
        mime: "image/gif"
      ),
      .init(
        name: "static-tiff",
        text: "Static image total is 42 dollars",
        type: .tiff,
        mime: "image/tiff"
      )
    ]
    for fixture in cases {
      let image = try await raster(fixture.text, type: fixture.type)
      let raw = message(image: image, mime: fixture.mime, disposition: fixture.disposition)
      let actual = await EmbeddedImageOCR().text(from: raw)
      try emit(fixture.name, result: actual == fixture.text ? "matched" : "different", text: actual)
      guard actual == fixture.text else { throw ProbeFailure.unexpected(fixture.name) }
    }
    let malformed = message(image: Data("not an image".utf8), mime: "image/png")
    let remote = Data(
      "Content-Type: text/html\n\n<img src=\"https://example.com/never-fetch.png\">".utf8
    )
    for (name, raw) in [("malformed", malformed), ("remote-only", remote)] {
      guard await EmbeddedImageOCR().text(from: raw) == nil else {
        throw ProbeFailure.unexpected(name)
      }
      try emit(name, result: "unknown")
    }
  }

  private static func inspectPrivacy() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try Store(url: directory.appending(path: "probe.store"))
    try await StateRepository.editSettings(store) { settings in
      settings.mailOptions.localOnly = true
      settings.advancedOptions.imageOCR = true
      settings.advancedOptions.domainRegistrationLookup = true
      var external = ExternalEvidenceSettings()
      external.domainBlocklist = true
      external.termsAcknowledged = true
      external.rspamcPath = "/opt/homebrew/bin/rspamc"
      settings.advancedOptions.externalEvidence = external
      settings.advancedOptions.mailSharingConsent = Set(ModelBackend.allCases)
    }
    let classifier = ConfiguredClassifier(store: store) { _ in throw ProbeFailure.credentialRead }
    let pipeline = Pipeline(store: store, classifier: classifier, rdap: RDAPLookup())
    let image = try await raster("Local evidence stays on this Mac", type: .png)
    let raw = message(image: image, mime: "image/png")
    let envelope = MailEnvelope(
      identity: MessageIdentity(accountID: "synthetic", contentHash: stableHash(raw)),
      raw: raw
    )
    for backend in ModelBackend.allCases {
      try await StateRepository.editSettings(store) { $0.advancedOptions.backend = backend }
      let record = await pipeline.process(envelope, forceDryRun: true)
      if backend != .onDevice {
        guard record.outcome == .unclassified,
          record.decision.reason == .classificationFailed(.configuration)
        else {
          throw ProbeFailure.unexpected(
            backend.rawValue + ": " + record.decision.reason.diagnosticDescription
          )
        }
      } else {
        guard record.outcome == .dryRun, record.verdict != nil else {
          throw ProbeFailure.unexpected("On-device classification did not complete")
        }
      }
      guard record.evidence?.domainAgeDays == nil,
        record.evidence?.auxiliaryFindings?.isEmpty != false
      else { throw ProbeFailure.unexpected("External evidence") }
      try emit(
        backend.rawValue,
        result: record.outcome.rawValue,
        text: record.decision.reason.diagnosticDescription
      )
    }
    let spending = try await SpendingLimit.load(store)
    guard spending.requests == 0, spending.committedMicroUSD == 0 else {
      throw ProbeFailure.unexpected("Paid request reservation")
    }
    try emit("paid-reservations", result: "zero")
    let unavailable = await RspamdLookup(executablePath: "/opt/homebrew/bin/rspamc").lookup(
      raw: raw
    )
    guard unavailable.status == .unknown else { throw ProbeFailure.unexpected("Missing rspamc") }
    try emit("missing-rspamc", result: "unknown")
  }

  private static func networkControl() async throws {
    guard let address = CommandLine.arguments.dropFirst(2).first,
      let url = URL(string: address), url.host == "127.0.0.1"
    else { throw ProbeFailure.fixture }
    let (data, _) = try await URLSession.shared.data(from: url)
    try emit("loopback-observer-control", result: "received \(data.count) bytes")
  }

  private static func inspectRspamd() async throws {
    let arguments = Array(CommandLine.arguments.dropFirst(2))
    guard arguments.count == 2, ["observed", "unknown"].contains(arguments[1]) else {
      throw ProbeFailure.fixture
    }
    let boundary = EvidenceProcess { path, arguments, input in
      do {
        return try await EvidenceProcess.live.run(
          executable: path,
          arguments: arguments,
          input: input
        )
      } catch {
        let diagnostic = error as NSError
        try emit("rspamd-process", result: "\(diagnostic.domain):\(diagnostic.code)")
        throw error
      }
    }
    let scanner = RspamdLookup(executablePath: arguments[0], process: boundary)
    try await inspectRspamd(scanner: scanner, expectedStatus: arguments[1])
  }

  private static func inspectRspamdHTTP() async throws {
    guard let expected = CommandLine.arguments.dropFirst(2).first,
      ["observed", "unknown"].contains(expected)
    else { throw ProbeFailure.fixture }
    try await inspectRspamd(
      scanner: RspamdLookup(transport: .loopbackHTTP),
      expectedStatus: expected
    )
  }

  private static func rawScannerFixture(_ body: String) -> Data {
    Data(
      "From: fixture@example.invalid\r\nTo: reader@example.invalid\r\n"
        .appending("Subject: Synthetic scanner probe\r\nMIME-Version: 1.0\r\n")
        .appending("Content-Type: text/plain; charset=utf-8\r\n\r\n\(body)\r\n").utf8
    )
  }

  private static func inspectRspamd(scanner: RspamdLookup, expectedStatus: String) async throws {
    for (name, body) in [("marker", "spamwiseprobe"), ("ordinary", "Hello reader")] {
      let finding = await scanner.lookup(raw: rawScannerFixture(body))
      guard finding.status.rawValue == expectedStatus else {
        throw ProbeFailure.unexpected("Rspamd \(name): \(finding.status.rawValue)")
      }
      if finding.status == .observed {
        let expected = name == "marker" ? ["SPAMWISE_PROBE: 1.5"] : []
        guard finding.details == expected else {
          throw ProbeFailure.unexpected("Rspamd symbols: \(finding.details)")
        }
      }
      try emit(
        "rspamd-\(name)",
        result: finding.status.rawValue,
        text: finding.details.joined(separator: ", ")
      )
    }
  }

  private static func inspectRspamdHTTPFaults() async throws {
    let scanner = RspamdLookup(transport: .loopbackHTTP)
    for mode in ["redirect", "overflow", "failure", "timeout"] {
      let start = ContinuousClock.now
      let finding = await scanner.lookup(raw: rawScannerFixture("\(mode)-probe"))
      guard finding.status == .unknown, start.duration(to: .now) < .seconds(5) else {
        throw ProbeFailure.unexpected("HTTP \(mode)")
      }
      try emit("http-\(mode)", result: "unknown")
    }
    let cancellation = Task { await scanner.lookup(raw: rawScannerFixture("cancel-probe")) }
    try await Task.sleep(for: .milliseconds(200))
    let start = ContinuousClock.now
    cancellation.cancel()
    guard await cancellation.value.status == .unknown, start.duration(to: .now) < .seconds(1) else {
      throw ProbeFailure.unexpected("HTTP cancellation")
    }
    try emit("http-cancellation", result: "unknown")
    async let marker = scanner.lookup(raw: rawScannerFixture("spamwiseprobe"))
    async let ordinary = scanner.lookup(raw: rawScannerFixture("Hello reader"))
    let findings = await (marker, ordinary)
    guard findings.0.status == .observed, findings.0.details == ["SPAMWISE_PROBE: 1.5"],
      findings.1.status == .observed, findings.1.details.isEmpty
    else { throw ProbeFailure.unexpected("HTTP concurrent isolation") }
    try emit("http-concurrent", result: "isolated")
  }
}
