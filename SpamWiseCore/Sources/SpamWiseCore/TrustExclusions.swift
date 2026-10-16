import Foundation

/// Explicit alias and sender exclusions from implicit relationship trust.
public enum TrustExclusions {
  private static let maximumAddresses = 100
  private static let maximumInputCharacters = 30_000
  /// Validates all addresses before replacing the exclusion set in one settings transaction.
  public static func save(_ text: String, store: Store) async throws {
    guard text.count <= maximumInputCharacters else { throw RuleManagementError.tooManyRules }
    let addresses = try text.split(whereSeparator: \.isNewline).map {
      try RuleManagement.normalized(String($0), scope: .address)
    }
    guard addresses.count <= maximumAddresses else { throw RuleManagementError.tooManyRules }
    try await StateRepository.editSettings(store) {
      $0.mailOptions.trustExclusions = Set(addresses)
    }
  }
}
