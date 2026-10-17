import Darwin
import Foundation
import PDFKit

// Synthetic evaluation only: production attachment parsing does not launch this executable.
private enum Limits {
  static let bytes = 524_288
  static let pages = 12
  static let characters = 3000
  static let seconds: TimeInterval = 3
}

private struct Result: Codable {
  var status: String
  var text: String = ""
}

private struct Fixture {
  var name: String
  var data: Data
  var expected: String
  var text: String = ""
  var mode = "extract"
}

private enum ProbeError: Error {
  case fixture, failed(String), resourceLimit
}

private func pdf(pages: Int = 1, text: String = "Synthetic offer", active: Bool = false) -> Data {
  let action =
    active
    ? " /OpenAction << /S /JavaScript /JS (app.alert('synthetic')) >>" : ""
  let children = (0..<pages).map { "\(4 + $0 * 2) 0 R" }.joined(separator: " ")
  var objects = [
    "<< /Type /Catalog /Pages 2 0 R\(action) >>",
    "<< /Type /Pages /Kids [\(children)] /Count \(pages) >>",
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"
  ]
  for index in 0..<pages {
    objects.append(
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] "
        + "/Resources << /Font << /F1 3 0 R >> >> /Contents \(5 + index * 2) 0 R >>"
    )
    let fontSize = text.count > 100 ? "0.1" : "12"
    let stream = "BT /F1 \(fontSize) Tf 36 750 Td (\(text)) Tj ET"
    objects.append("<< /Length \(stream.utf8.count) >>\nstream\n\(stream)\nendstream")
  }
  var output = "%PDF-1.7\n", offsets: [Int] = []
  for (index, object) in objects.enumerated() {
    offsets.append(output.utf8.count)
    output += "\(index + 1) 0 obj\n\(object)\nendobj\n"
  }
  let start = output.utf8.count
  output += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
  for offset in offsets {
    let digits = String(offset)
    output += String(repeating: "0", count: 10 - digits.count) + digits + " 00000 n \n"
  }
  output += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(start)\n%%EOF\n"
  return Data(output.utf8)
}

private func encryptedPDF(password: String) throws -> Data {
  guard let document = PDFDocument(data: pdf()),
    let data = document.dataRepresentation(options: [
      PDFDocumentWriteOption.ownerPasswordOption: "synthetic-owner",
      PDFDocumentWriteOption.userPasswordOption: password
    ])
  else { throw ProbeError.fixture }
  return data
}

private func fixtures() throws -> [Fixture] {
  [
    Fixture(name: "text", data: pdf(), expected: "extracted", text: "Synthetic offer"),
    Fixture(
      name: "active-content",
      data: pdf(active: true),
      expected: "extracted",
      text: "Synthetic offer"
    ),
    Fixture(
      name: "encrypted",
      data: try encryptedPDF(password: "synthetic"),
      expected: "encrypted"
    ),
    Fixture(name: "owner-encrypted", data: try encryptedPDF(password: ""), expected: "encrypted"),
    Fixture(name: "malformed", data: Data("%PDF-1.7\nbroken".utf8), expected: "malformed"),
    Fixture(
      name: "oversized",
      data: Data(repeating: 0, count: Limits.bytes + 1),
      expected: "byte-limit"
    ),
    Fixture(name: "page-limit", data: pdf(pages: Limits.pages + 1), expected: "page-limit"),
    Fixture(
      name: "text-limit",
      data: pdf(text: String(repeating: "x", count: Limits.characters + 100)),
      expected: "extracted",
      text: String(repeating: "x", count: Limits.characters)
    ),
    Fixture(name: "hung-worker", data: Data(), expected: "timeout", mode: "hang"),
    Fixture(name: "crashed-worker", data: Data(), expected: "worker-failed", mode: "crash")
  ]
}

private func extract(_ url: URL) throws -> Result {
  let handle = try FileHandle(forReadingFrom: url)
  defer { try? handle.close() }
  let data = try handle.read(upToCount: Limits.bytes + 1) ?? Data()
  guard data.count <= Limits.bytes else { return Result(status: "byte-limit") }
  guard let document = PDFDocument(data: data) else { return Result(status: "malformed") }
  guard !document.isEncrypted, !document.isLocked else { return Result(status: "encrypted") }
  guard document.pageCount > 0, document.pageCount <= Limits.pages else {
    return Result(status: "page-limit")
  }
  var text = ""
  for index in 0..<document.pageCount {
    guard let page = document.page(at: index), let pageText = page.string else {
      return Result(status: "unreadable")
    }
    text += pageText.prefix(Limits.characters - text.count)
    if text.count == Limits.characters { break }
    text += "\n"
  }
  return Result(status: "extracted", text: text.trimmingCharacters(in: .whitespacesAndNewlines))
}

private func worker(mode: String, url: URL) throws {
  var cpu = rlimit(rlim_cur: 2, rlim_max: 2)
  guard unsafe setrlimit(RLIMIT_CPU, &cpu) == 0 else { throw ProbeError.resourceLimit }
  if mode == "hang" { Thread.sleep(forTimeInterval: 60) }
  if mode == "crash" { exit(42) }
  let result = try extract(url)
  try FileHandle.standardOutput.write(contentsOf: JSONEncoder().encode(result))
}

private func evaluate(_ fixture: Fixture, in directory: URL) throws -> Result {
  let url = directory.appendingPathComponent(fixture.name + ".pdf")
  try fixture.data.write(to: url)
  let child = Process(), pipe = Pipe()
  child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
  child.arguments = ["worker", fixture.mode, url.path]
  child.standardOutput = pipe
  child.standardError = FileHandle.nullDevice
  try child.run()
  let deadline = ProcessInfo.processInfo.systemUptime + Limits.seconds
  while child.isRunning, ProcessInfo.processInfo.systemUptime < deadline {
    Thread.sleep(forTimeInterval: 0.01)
  }
  if child.isRunning {
    kill(child.processIdentifier, SIGKILL)
    child.waitUntilExit()
    return Result(status: "timeout")
  }
  child.waitUntilExit()
  guard child.terminationStatus == 0 else { return Result(status: "worker-failed") }
  let output = try pipe.fileHandleForReading.read(upToCount: 32_768) ?? Data()
  return try JSONDecoder().decode(Result.self, from: output)
}

private func run() throws {
  if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "worker" {
    try worker(mode: CommandLine.arguments[2], url: URL(fileURLWithPath: CommandLine.arguments[3]))
    return
  }
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
  defer { try? FileManager.default.removeItem(at: directory) }
  for fixture in try fixtures() {
    let result = try evaluate(fixture, in: directory)
    guard result.status == fixture.expected, result.text == fixture.text else {
      throw ProbeError.failed("\(fixture.name): \(result.status), \(result.text.count) characters")
    }
    print("\(fixture.name): \(result.status), \(result.text.count) characters")
  }
}

do {
  try run()
} catch {
  try? FileHandle.standardError.write(contentsOf: Data("Document probe failed: \(error)\n".utf8))
  exit(1)
}
