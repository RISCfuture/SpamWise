/// Compile-time distribution boundaries; unavailable features cannot be enabled by restored preferences.
public enum DistributionCapabilities {
  /// Whether separately installed executable evidence is part of this distribution.
  public static var externalPrograms: Bool {
    #if APP_STORE
      false
    #else
      true
    #endif
  }
  /// Whether the ungranted PCC option may be presented for explicit experimental setup.
  public static var privateCloudCompute: Bool {
    #if APP_STORE
      false
    #else
      true
    #endif
  }
}
