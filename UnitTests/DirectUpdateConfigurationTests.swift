import Foundation
import Testing
@testable import SpamWiseCommon

@Suite
// swiftlint:disable:next type_name
struct `checks only a valid GitHub repository` {
  @Test(arguments: ["", "$(UPDATE_OWNER)", "../owner", "-owner", "owner-", "a--b", "a/b", "é"])
  func `rejects unsafe or unconfigured owners`(_ owner: String) {
    #expect(DirectUpdateConfiguration(owner: owner, repository: "SpamWise") == nil)
  }

  @Test(arguments: [
    "", "$(UPDATE_REPOSITORY)", ".", "..", "../SpamWise", "a/b", "a?b", "a#b", "a%2Fb"
  ])
  func `rejects unsafe or unconfigured repositories`(_ repository: String) {
    #expect(DirectUpdateConfiguration(owner: "publisher", repository: repository) == nil)
  }

  @Test func `accepts GitHub owner and repository names`() throws {
    let configuration = try #require(
      DirectUpdateConfiguration(owner: "test-publisher", repository: "test.app_1")
    )
    #expect(configuration.owner == "test-publisher")
    #expect(configuration.repository == "test.app_1")
  }

  @Test func `reads only SpamWise bundles without store receipts`() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(
      DirectUpdateConfiguration(bundle: try makeBundle(root: root))?.owner == "test-publisher"
    )
    let other = try makeBundle(root: root, identifier: "codes.tim.Other")
    #expect(DirectUpdateConfiguration(bundle: other) == nil)
    let unconfigured = try makeBundle(root: root, owner: nil)
    #expect(DirectUpdateConfiguration(bundle: unconfigured) == nil)
    let receipt = try makeBundle(root: root, hasReceipt: true)
    #expect(DirectUpdateConfiguration(bundle: receipt) == nil)
  }

  private func makeBundle(
    root: URL,
    identifier: String = "codes.tim.SpamWise",
    owner: String? = "test-publisher",
    hasReceipt: Bool = false
  ) throws -> Bundle {
    let url = root.appending(path: "\(UUID().uuidString).app")
    let contents = url.appending(path: "Contents")
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    var info = ["CFBundleIdentifier": identifier, "SpamWiseUpdateRepository": "test-app"]
    info["SpamWiseUpdateOwner"] = owner
    let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    try data.write(to: contents.appending(path: "Info.plist"))
    if hasReceipt {
      let directory = contents.appending(path: "_MASReceipt")
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try Data().write(to: directory.appending(path: "receipt"))
    }
    return try #require(Bundle(url: url))
  }
}
