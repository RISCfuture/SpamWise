import Foundation

/// One-sided Clopper-Pearson 95% upper confidence bounds for a binomial error rate.
public enum BinomialBound {
  private static let upperTailProbability = 0.05
  private static let bisectionIterations = 70
  /// Returns nil for an empty sample; zero-error samples use the exact closed form.
  public static func upper95(errors: Int, trials: Int) -> Double? {
    guard trials > 0, (0...trials).contains(errors) else { return nil }
    if errors == trials { return 1 }
    if errors == 0 { return 1 - pow(upperTailProbability, 1 / Double(trials)) }
    var low = Double(errors) / Double(trials), high = 1.0
    for _ in 0..<bisectionIterations {
      let probability = (low + high) / 2
      if cumulative(errors: errors, trials: trials, probability: probability) > upperTailProbability
      {
        low = probability
      } else {
        high = probability
      }
    }
    return high
  }
  private static func cumulative(errors: Int, trials: Int, probability: Double) -> Double {
    var term = Double(trials) * log1p(-probability)
    var terms = [term]
    for index in 1...errors {
      term +=
        log(Double(trials - index + 1)) - log(Double(index)) + log(probability)
        - log1p(-probability)
      terms.append(term)
    }
    let peak = terms.max() ?? 0
    return exp(peak) * terms.reduce(0) { $0 + exp($1 - peak) }
  }
}
