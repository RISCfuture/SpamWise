import ArgumentParser
import Foundation
import MailIntegration
import SpamWiseCore

/// The `--config` option every command takes.
struct ConfigurationOptions: ParsableArguments {
  private static let maximumConfigurationBytes = 65_536

  @Option(help: "Path to the JSON connection configuration.")
  var config: String

  func validate() throws {
    guard !config.isEmpty else { throw DaemonUsageError.missingConfiguration }
  }

  /// Reads at most 64 KiB of configuration and opens its store.
  func load() throws -> DaemonContext {
    let file = try FileHandle(forReadingFrom: URL(filePath: config))
    defer { try? file.close() }
    let data = try file.read(upToCount: Self.maximumConfigurationBytes + 1) ?? Data()
    let configuration = try IMAPDaemonConfiguration.decode(data)
    let store = try Store(
      url: configuration.statePath.map { URL(filePath: $0) } ?? Store.sharedURL()
    )
    return DaemonContext(configuration: configuration, store: store)
  }
}

/// A loaded configuration and the store it selects.
struct DaemonContext {
  let configuration: IMAPDaemonConfiguration
  let store: Store

  /// Whether the store is the one the app shares, rather than a daemon-only `statePath`.
  var usesSharedStore: Bool { configuration.statePath == nil }

  /// An adapter whose actions require daemon-scoped validation and the `allowsActions` option.
  func adapter(allowingActions: Bool) -> IMAPAdapter {
    var account = configuration.account
    account.allowsActions = allowingActions
    let credential = configuration.credential
    return IMAPAdapter(
      configuration: account,
      credentials: { try credential.resolve() },
      validations: store,
      validationScope: .daemon
    )
  }

  /// A classifier using the configuration's provider credential references, or the shared Keychain.
  func classifier() -> ConfiguredClassifier {
    guard let references = configuration.providerCredentials else {
      return ConfiguredClassifier(store: store)
    }
    return ConfiguredClassifier(store: store) { backend in
      guard let reference = references[backend.rawValue] else {
        throw ClassificationError.missingCredential
      }
      return try reference.resolvedSecret()
    }
  }

  /// Runs `change`, then prints every shared setting it changed.
  func reportingSettingChanges(_ change: () async throws -> Void) async throws {
    let before = try await StateRepository.load(store, StateSlices()).settings
    try await change()
    let after = try await StateRepository.load(store, StateSlices()).settings
    print(settingChangesReport(after.changedFields(from: before)))
  }

  private func settingChangesReport(_ changed: [String]) -> String {
    let fields = changed.joined(separator: ", ")
    return switch (usesSharedStore, changed.isEmpty) {
      case (true, true):
        String(localized: "No settings changed in the store shared with the app.", bundle: .module)
      case (true, false):
        String(
          localized: "Changed settings in the store shared with the app: \(fields).",
          bundle: .module
        )
      case (false, true):
        String(localized: "No settings changed in this daemon’s store.", bundle: .module)
      case (false, false):
        String(localized: "Changed settings in this daemon’s store: \(fields).", bundle: .module)
    }
  }
}
