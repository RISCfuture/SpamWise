import Foundation
import Testing
import SpamWiseCore
@testable import SpamWiseCommon

@MainActor
@Suite
struct `Trust exception edits` {
  @Test
  func `keep an edit that can't be saved until it is corrected`() async throws {
    let store = try Store(
      url: FileManager.default.temporaryDirectory
        .appending(path: "SpamWise-UnitTests-\(UUID())/state.store")
    )
    let shared = SharedStateModel(store: store)
    let relationships = RelationshipsModel(services: services(store: store), shared: shared)
    await shared.refresh()

    relationships.exclusionsText = "not an address"
    await relationships.commitTrustExclusions().value
    #expect(relationships.exclusionsText == "not an address")
    #expect(relationships.exclusions.failure != nil)

    relationships.exclusionsText = "friend@example.org"
    await relationships.commitTrustExclusions().value
    #expect(relationships.exclusionsEdit == nil)
    #expect(relationships.exclusionsText == "friend@example.org")
    let saved = try await StateRepository.load(store, StateSlices()).settings
    #expect(saved.mailOptions.trustExclusions == ["friend@example.org"])
  }

  /// Preview services over `store`, so saving reaches real storage and Mail is never asked.
  private func services(store: Store) -> AppServices {
    let preview = AppServices.preview()
    return AppServices(
      store: store,
      pipeline: nil,
      appleMail: preview.appleMail,
      preferences: preview.preferences,
      uiTesting: true
    )
  }
}
