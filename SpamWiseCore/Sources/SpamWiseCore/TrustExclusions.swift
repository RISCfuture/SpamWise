public import Foundation

/// Failures while saving trust exclusions.
public protocol TrustExclusionFailure: Error {}

/// Why a trust-exclusion list was rejected; the saved list is unchanged.
public enum TrustExclusionError: TrustExclusionFailure, Sendable, Equatable, LocalizedError {
  /// The pasted text is longer than the supported input.
  case inputTooLong(limit: Int)
  /// The list holds more addresses than the supported maximum.
  case tooManyAddresses(limit: Int)
  /// One line is not a complete email address.
  case invalidAddress(String)
  /// A general description of the rejected exclusion list.
  public var errorDescription: String? {
    String(localized: "The trust exclusions couldn’t be saved.")
  }
  /// The constraint that rejected the list.
  public var failureReason: String? {
    switch self {
      case .inputTooLong(let limit):
        String(localized: "Enter at most \(limit, format: .number) characters.")
      case .tooManyAddresses(let limit):
        String(localized: "Enter at most \(limit, format: .number) addresses.")
      case .invalidAddress(let line):
        String(localized: "“\(line)” is not a complete email address.")
    }
  }
}

/// Explicit alias and sender exclusions from implicit relationship trust.
public enum TrustExclusions {
  private static let maximumAddresses = 100
  private static let maximumInputCharacters = 30_000
  private static let maximumQuotedLineCharacters = 80
  /// Validates all addresses before replacing the exclusion set in one settings transaction.
  public static func save(_ text: String, store: Store) async throws {
    guard text.count <= maximumInputCharacters else {
      throw TrustExclusionError.inputTooLong(limit: maximumInputCharacters)
    }
    let addresses = try text.split(whereSeparator: \.isNewline).map(address)
    guard addresses.count <= maximumAddresses else {
      throw TrustExclusionError.tooManyAddresses(limit: maximumAddresses)
    }
    try await StateRepository.editSettings(store) {
      $0.mailOptions.trustExclusions = Set(addresses)
    }
  }
  private static func address(_ line: Substring) throws -> String {
    do { return try RuleManagement.normalized(String(line), scope: .address) } catch {
      throw TrustExclusionError.invalidAddress(
        String(line.trimmingCharacters(in: .whitespaces).prefix(maximumQuotedLineCharacters))
      )
    }
  }
}
