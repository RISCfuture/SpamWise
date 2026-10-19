public import Foundation

/// Standard USD rates per million tokens, stored with source and verification date.
public struct ModelTokenPricing: Codable, Sendable, Equatable {
  private static let geminiStandardPricingDate = Date(timeIntervalSince1970: 1_798_761_600)
  private static let geminiStandardPriceMultiplier = 2.0
  static let legacyHaiku = Self(
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

  /**
   Creates rates in USD per million tokens.

   - Parameters:
     - input: Uncached input rate.
     - output: Output rate, including billed reasoning tokens.
     - cached: Cached input rate.
     - source: Where the rates came from, such as an official pricing page.
     - verified: Date the source was verified, in ISO calendar format.
   */
  public init(input: Double, output: Double, cached: Double, source: String, verified: String) {
    self.input = input; self.output = output; self.cached = cached
    self.source = source; self.verified = verified
  }

  /// Returns the standard rates captured for a supported model at `date`.
  public static func rates(for model: ModelIdentifier, at date: Date = .now) -> Self {
    let anthropic = "https://platform.claude.com/docs/en/about-claude/pricing"
    switch model {
      case .claudeHaiku: return .legacyHaiku
      case .claudeSonnet:
        return .init(input: 2, output: 10, cached: 0.10, source: anthropic, verified: "2026-10-16")
      case .claudeOpus:
        return .init(input: 4, output: 20, cached: 0.20, source: anthropic, verified: "2026-10-16")
      case .gptMini:
        return .init(
          input: 0.75,
          output: 4.50,
          cached: 0.075,
          source: "https://developers.openai.com/api/docs/models/gpt-5.4-mini",
          verified: "2026-10-16"
        )
      case .geminiFlash:
        let multiplier = date < geminiStandardPricingDate ? 1.0 : geminiStandardPriceMultiplier
        return .init(
          input: 0.75 * multiplier,
          output: 3.75 * multiplier,
          cached: 0.075 * multiplier,
          source: "https://ai.google.dev/gemini-api/docs/pricing",
          verified: "2026-10-16"
        )
      case .appleOnDevice, .applePrivateCloudCompute:
        return .init(
          input: 0,
          output: 0,
          cached: 0,
          source: "https://developer.apple.com/documentation/foundationmodels",
          verified: "2026-10-16"
        )
    }
  }
}

extension ModelTokenPricing {
  private static let requestFramingTokens = 1_024

  /**
   Upper-bound USD for one request at these rates.

   Each prompt and instruction byte counts as an uncached input token, plus an allowance for
   request framing and the output schema, and the full response-token limit counts as output.
   */
  public func maximumCost(of input: ClassificationInput) throws -> Double {
    let inputTokens =
      try PromptBuilder.prompt(input).utf8.count + PromptBuilder.instructions.utf8.count
      + Self.requestFramingTokens
    return TokenUsage(
      input: inputTokens,
      output: ClassificationLimits.maximumResponseTokens,
      pricing: self
    ).estimatedCost
  }
}
