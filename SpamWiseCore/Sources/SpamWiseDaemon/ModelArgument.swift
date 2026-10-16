public import ArgumentParser
public import SpamWiseCore

extension ModelIdentifier: ExpressibleByArgument {
  /// Every model the daemon accepts; Private Cloud Compute is not offered.
  public static var allValueStrings: [String] {
    allCases.filter { $0 != .applePrivateCloudCompute }.map(\.rawValue)
  }

  /// Parses an offered model identifier.
  public init?(argument: String) {
    guard Self.allValueStrings.contains(argument), let model = Self(rawValue: argument) else {
      return nil
    }
    self = model
  }
}
