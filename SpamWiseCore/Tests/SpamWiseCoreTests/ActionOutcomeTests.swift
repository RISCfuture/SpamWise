import Foundation
import Testing
import SpamWiseCore

@Test func `records action failures separately from verdicts`() async throws {
  let store = try testStore(), adapter = RecordingAdapter()
  await adapter.deny(); try await enableActions(store)
  let pipeline = Pipeline(
    store: store,
    classifier: MockClassifier(verdict: .init(label: .review, confidence: 50, reason: "uncertain"))
  )
  let record = await pipeline.process(try envelope(), adapter: adapter)
  #expect(record.verdict?.label == .review)
  #expect(record.outcome == .failed)
  #expect(record.actionError != nil)
  let rejection = ActionNotAttempted(cause: IntegrationError.staleMessage)
  await adapter.deny(with: rejection)
  let rejected = await pipeline.process(try envelope("personal"), adapter: adapter)
  #expect(rejected.actionError?.hasPrefix(try #require(rejection.errorDescription)) == true)
  await adapter.refuse(.orangeFlag)
  let unsupported = await pipeline.process(try envelope("unsolicited-newsletter"), adapter: adapter)
  let state = try await StateRepository.load(store)
  #expect(unsupported.outcome == .noAction && unsupported.actionError != nil)
  #expect(state.claimedActions[unsupported.identity.key] == nil)
  #expect(await adapter.actions.isEmpty)
}
