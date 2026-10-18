import SpamWiseCore

/// Whether the selected provider can classify mail, or what it still needs.
enum ClassifierReadiness: Equatable {
  /// The provider can classify mail now.
  case ready
  /// Keeping filtering on this Mac blocks the selected cloud provider.
  case blockedByLocalOnly
  /// The provider can't run on this Mac or in this edition.
  case unavailable
  /// The provider has no API key saved in Keychain.
  case needsKey
  /// The user hasn't allowed mail to be sent to the provider.
  case needsConsent

  /// Whether messages the rules can't decide will be classified.
  var isReady: Bool { self == .ready }

  /**
   Assesses the provider selected in `settings`.

   - Parameters:
     - settings: The shared settings, which select the provider and record consent.
     - onDeviceAvailable: Whether Apple's on-device model can run on this Mac.
     - savedKeys: The providers whose API keys are saved in Keychain.
   */
  init(
    settings: SpamWiseCore.Settings,
    onDeviceAvailable: Bool,
    savedKeys: Set<ModelBackend>
  ) {
    let backend = settings.advancedOptions.backend
    switch backend {
      case .onDevice: self = onDeviceAvailable ? .ready : .unavailable
      case .privateCloudCompute: self = .unavailable
      case .claude, .openAI, .gemini:
        if settings.mailOptions.localOnly {
          self = .blockedByLocalOnly
        } else if !savedKeys.contains(backend) {
          self = .needsKey
        } else if !settings.advancedOptions.mailSharingConsent.contains(backend) {
          self = .needsConsent
        } else {
          self = .ready
        }
    }
  }
}

extension ModelBackend {
  /// The providers a user can choose, in the order setup and Settings list them.
  static let selectable: [Self] = [.onDevice, .claude, .openAI, .gemini]

  /// Whether this provider receives mail over the network and needs an API key.
  var isCloud: Bool {
    switch self {
      case .claude, .openAI, .gemini: true
      case .onDevice, .privateCloudCompute: false
    }
  }
}
