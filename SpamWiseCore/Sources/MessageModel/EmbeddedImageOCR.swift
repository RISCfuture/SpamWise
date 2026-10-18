public import Foundation
import Vision

/// Optional local text recognition of bounded, embedded raster images only.
public struct EmbeddedImageOCR: Sendable {
  private static let maximumTextCharacters = 3000
  private static let maximumObservations = 100
  private static let recognitionTimeoutSec: TimeInterval = 3
  private let recognize: @Sendable (Data) async throws -> String

  /// Uses native Vision by default; an injected recognizer receives only prevalidated image bytes.
  public init(recognize: (@Sendable (Data) async throws -> String)? = nil) {
    self.recognize = recognize ?? Self.recognize
  }

  private static func recognize(_ data: Data) async throws -> String {
    var request = RecognizeTextRequest()
    request.recognitionLevel = .fast
    request.automaticallyDetectsLanguage = true
    request.usesLanguageCorrection = false
    let observations = try await request.perform(on: data)
    return observations.prefix(maximumObservations).compactMap { $0.topCandidates(1).first?.string }
      .joined(
        separator: "\n"
      )
  }

  /// Returns bounded untrusted OCR text, or nil for absent images, invalid input or unavailable recognition.
  public func text(from parts: [InlineImage]) async -> String? {
    do {
      let images = try EmbeddedImages().extract(from: parts)
      guard !images.isEmpty else { return nil }
      return try await withResourceDeadline(seconds: Self.recognitionTimeoutSec) {
        try await recognizedText(in: images)
      }
    } catch { return nil }
  }

  private func recognizedText(in images: [Data]) async throws -> String? {
    var results: [String] = [], remaining = Self.maximumTextCharacters
    for image in images {
      try Task.checkCancellation()
      let result = try await recognize(image).trimmingCharacters(in: .whitespacesAndNewlines)
      if !result.isEmpty {
        let bounded = String(result.prefix(remaining))
        results.append(bounded)
        remaining -= bounded.count
      }
      if remaining == 0 { break }
    }
    return results.isEmpty
      ? nil
      : String(results.joined(separator: "\n").prefix(Self.maximumTextCharacters))
  }
}
