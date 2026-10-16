public import Foundation

/// Standard USD rates per million tokens, stored with source and verification date.
public struct ModelTokenPricing: Codable, Sendable, Equatable {
  private static let geminiStandardPricingDate = Date(timeIntervalSince1970: 1_798_761_600)
  private static let geminiStandardPriceMultiplier = 2.0
  static let legacyHaiku = ModelTokenPricing(
    input: 0.10,
    output: 0.50,
    cached: 0.01,
    source: "https://platform.claude.com/docs/en/about-claude/pricing",
    verified: "2026-10-16"
  )
  /// Uncached input rate.
  public let input: Double
  /// Output rate, including billed reasoning tokens.
  public let output: Double
  /// Cached input rate.
  public let cached: Double
  /// Official source for the captured rates.
  public let source: String
  /// Date the source was verified, in ISO calendar format.
  public let verified: String

  /// Returns explicit supported-model rates, rejecting unknown model names.
  public static func rates(for modelID: String, at date: Date = .now) throws -> Self {
    let anthropic = "https://platform.claude.com/docs/en/about-claude/pricing"
    switch modelID {
      case "claude-haiku-5-5": return .legacyHaiku
      case "claude-sonnet-5-5":
        return .init(input: 2, output: 10, cached: 0.10, source: anthropic, verified: "2026-10-16")
      case "claude-opus-5-5":
        return .init(input: 4, output: 20, cached: 0.20, source: anthropic, verified: "2026-10-16")
      case "gpt-5.4-mini":
        return .init(
          input: 0.75,
          output: 4.50,
          cached: 0.075,
          source: "https://developers.openai.com/api/docs/models/gpt-5.4-mini",
          verified: "2026-10-16"
        )
      case "gemini-3.8-flash":
        let multiplier = date < geminiStandardPricingDate ? 1.0 : geminiStandardPriceMultiplier
        return .init(
          input: 0.75 * multiplier,
          output: 3.75 * multiplier,
          cached: 0.075 * multiplier,
          source: "https://ai.google.dev/gemini-api/docs/pricing",
          verified: "2026-10-16"
        )
      case "apple-on-device", "apple-private-cloud-compute":
        return .init(
          input: 0,
          output: 0,
          cached: 0,
          source: "https://developer.apple.com/documentation/foundationmodels",
          verified: "2026-10-16"
        )
      default: throw ClassificationError.configuration
    }
  }
}
