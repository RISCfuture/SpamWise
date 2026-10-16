#if SPAMWISE_DIRECT_UPDATES && APP_STORE
  #error("The direct update target cannot be used for App Store distribution.")
#endif

#if SPAMWISE_DIRECT_UPDATES && !APP_STORE
  import Foundation
  import GitHubReleaseDiscovery
  import Observation

  @MainActor @Observable final class DirectUpdateModel {
    private(set) var isChecking = false
    private(set) var status: String?
    private(set) var hasUpdate = false
    let configuration: DirectUpdateConfiguration?
    private let checker: GitHubAPIClient?
    private let currentVersion: SemanticVersion?
    var canCheck: Bool { checker != nil && !isChecking }

    init(configuration: DirectUpdateConfiguration? = DirectUpdateConfiguration()) {
      self.configuration = configuration
      if configuration != nil,
        let versionString = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
          as? String,
        let version = SemanticVersion(versionString)
      {
        currentVersion = version
        checker = GitHubAPIClient()
      } else {
        currentVersion = nil
        checker = nil
      }
    }

    func check() async {
      guard let checker, let configuration, let currentVersion, !isChecking else { return }
      isChecking = true
      hasUpdate = false
      status = nil
      defer { isChecking = false }
      do {
        let release = try await checker.fetchLatestRelease(
          owner: configuration.owner,
          repo: configuration.repository
        )
        guard !release.draft, !release.prerelease, let version = release.version else {
          status = String(localized: "No stable update is available.")
          return
        }
        hasUpdate = version > currentVersion
        status =
          hasUpdate
          ? String(localized: "Version \(version.description) is available.")
          : String(localized: "You’re up to date.")
      } catch {
        status = String(localized: "Couldn’t check for updates. Try again later.")
      }
    }
  }
#endif
