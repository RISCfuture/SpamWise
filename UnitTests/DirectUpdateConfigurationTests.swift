import Foundation
import Testing
@testable import SpamWise

struct DirectUpdateConfigurationTests {
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

  @Test func `constructs release links from explicit repository identity`() throws {
    let configuration = try #require(
      DirectUpdateConfiguration(owner: "test-publisher", repository: "test.app_1")
    )
    #expect(
      configuration.releasesURL.absoluteString
        == "https://github.com/test-publisher/test.app_1/releases"
    )
  }

  @Test func `restricts configured checks to direct bundles without store receipts`() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let direct = try makeBundle(root: root, channel: "direct")
    #expect(DirectUpdateConfiguration(bundle: direct)?.owner == "test-publisher")
    let store = try makeBundle(root: root, channel: "app-store")
    #expect(DirectUpdateConfiguration(bundle: store) == nil)
    let other = try makeBundle(root: root, channel: "direct", identifier: "codes.tim.Other")
    #expect(DirectUpdateConfiguration(bundle: other) == nil)
    let receipt = try makeBundle(root: root, channel: "direct", hasReceipt: true)
    #expect(DirectUpdateConfiguration(bundle: receipt) == nil)
  }

  private func makeBundle(
    root: URL,
    channel: String,
    identifier: String = "codes.tim.SpamWise",
    hasReceipt: Bool = false
  ) throws -> Bundle {
    let url = root.appending(path: "\(UUID().uuidString).app")
    let contents = url.appending(path: "Contents")
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    let info = [
      "CFBundleIdentifier": identifier,
      "SpamWiseDistribution": channel,
      "SpamWiseUpdateOwner": "test-publisher",
      "SpamWiseUpdateRepository": "test-app"
    ]
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
