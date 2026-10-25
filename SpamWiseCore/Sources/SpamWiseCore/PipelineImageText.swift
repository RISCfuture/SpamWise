import Foundation

extension Pipeline {
  /// The text in the embedded images of `raw`, reused from an earlier pass that the spending
  /// limit deferred, or else recognized now.
  func imageText(in images: [InlineImage], of raw: Data) async -> RecognizedImageText {
    let content = stableHash(raw)
    if let remembered = deferredImageTexts.text(for: content) {
      return RecognizedImageText(content: content, text: remembered)
    }
    return RecognizedImageText(content: content, text: await imageOCR.text(from: images))
  }
  /// Keeps `recognized` while the spending limit defers its message, and forgets it otherwise.
  func retain(_ recognized: RecognizedImageText, after record: DecisionRecord) {
    if record.deferredBySpendingLimit {
      deferredImageTexts.remember(recognized)
    } else {
      deferredImageTexts.forget(recognized.content)
    }
  }
}

/// Text recognized in one message's embedded images.
struct RecognizedImageText: Sendable {
  /// Digest of the raw message the images came from.
  let content: String
  /// The recognized text, or nil when the images held none or could not be recognized.
  let text: String?
}

/**
 Image text of messages the spending limit deferred, by raw-message digest, so every later
 sweep of a deferred message reuses its text instead of recognizing its images again.

 It forgets the oldest message once full. A sweep stops paging at a page of deferred messages,
 so the capacity covers several accounts' deferred pages.
 */
struct DeferredImageTexts: Sendable {
  private static let capacity = 500
  private var texts: [String: RecognizedImageText] = [:]
  private var order: [String] = []

  /// The text remembered for the message with digest `content`: nil when none is remembered,
  /// and `.some(nil)` when its images held no text.
  func text(for content: String) -> String?? { texts[content].map(\.text) }
  /// Remembers `recognized`, forgetting the oldest message when full.
  mutating func remember(_ recognized: RecognizedImageText) {
    guard texts.updateValue(recognized, forKey: recognized.content) == nil else { return }
    order.append(recognized.content)
    if order.count > Self.capacity { texts.removeValue(forKey: order.removeFirst()) }
  }
  /// Forgets the message with digest `content`.
  mutating func forget(_ content: String) {
    guard texts.removeValue(forKey: content) != nil else { return }
    order.removeAll { $0 == content }
  }
}
