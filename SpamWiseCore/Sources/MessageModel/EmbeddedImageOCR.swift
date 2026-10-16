public import Foundation
import Vision

/// Optional local text recognition of bounded, embedded raster images only.
public struct EmbeddedImageOCR: Sendable {
  private let recognize: @Sendable (Data) async throws -> String

  /// Uses native Vision by default; an injected recognizer receives only prevalidated image bytes.
  public init(recognize: (@Sendable (Data) async throws -> String)? = nil) {
    self.recognize = recognize ?? Self.recognize
  }

  /// Returns bounded untrusted OCR text, or nil for absent images, invalid input or unavailable recognition.
  public func text(from raw: Data) async -> String? {
    do {
      let images = try EmbeddedImages().extract(from: raw)
      guard !images.isEmpty else { return nil }
      return try await withResourceDeadline(seconds: 3) {
        var results: [String] = [], remaining = 3000
        for image in images {
          try Task.checkCancellation()
          let result = try await recognize(image).trimmingCharacters(in: .whitespacesAndNewlines)
          if !result.isEmpty {
            let bounded = String(result.prefix(remaining))
            results.append(bounded); remaining -= bounded.count
          }
          if remaining == 0 { break }
        }
        return results.isEmpty ? nil : String(results.joined(separator: "\n").prefix(3000))
      }
    } catch { return nil }
  }

  private static func recognize(_ data: Data) async throws -> String {
    var request = RecognizeTextRequest()
    request.recognitionLevel = .fast
    request.automaticallyDetectsLanguage = true
    request.usesLanguageCorrection = false
    let observations = try await request.perform(on: data)
    return observations.prefix(100).compactMap { $0.topCandidates(1).first?.string }.joined(
      separator: "\n"
    )
  }
}
