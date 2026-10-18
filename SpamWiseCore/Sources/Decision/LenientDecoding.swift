/// A string-backed enumeration that decodes values written by a newer version to a conservative case.
public protocol FallbackDecodable: RawRepresentable, Decodable where RawValue == String {
  /// The case used for an unrecognized raw value.
  static var fallback: Self { get }
}

extension FallbackDecodable {
  /// Decodes a known raw value, or ``fallback`` for an unrecognized one.
  public init(from decoder: any Decoder) throws {
    let raw = try decoder.singleValueContainer().decode(String.self)
    self = Self(rawValue: raw) ?? .fallback
  }
}

extension KeyedDecodingContainer {
  /**
   Decodes a field that may be absent, or unreadable because a different version wrote it.

   - Returns: The decoded value, or `fallback` when the key is missing or its value cannot be read.
   */
  public func lenient<T: Decodable>(_ key: Key, default fallback: T) -> T {
    ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
  }
}

extension ActionOutcome: FallbackDecodable {
  /// An unrecognized outcome may have dispatched an action, so it is treated as requested.
  public static var fallback: Self { .requested }
}

extension MailAction: FallbackDecodable {
  /// An unrecognized action is never performed.
  public static var fallback: Self { .none }
}

extension FilteringStrength: FallbackDecodable {
  /// An unrecognized strength uses the highest Junk threshold.
  public static var fallback: Self { .conservative }
}

extension ReviewTreatment: FallbackDecodable {
  /// An unrecognized treatment uses the default orange flag.
  public static var fallback: Self { .orangeFlag }
}
