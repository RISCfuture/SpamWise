public import Foundation

/**
 The GitHub repository the downloadable edition checks for releases.

 The values come from the edition's Info.plist, which `Config/SpamWise.xcconfig`
 fills in. A build without them, or one carrying a Mac App Store receipt, has
 no configuration and never checks.
 */
public struct DirectUpdateConfiguration: Equatable, Sendable {
  private static let bundleIdentifier = "codes.tim.SpamWise"
  private static let ownerKey = "SpamWiseUpdateOwner"
  private static let repositoryKey = "SpamWiseUpdateRepository"
  private static let receiptPath = "Contents/_MASReceipt/receipt"

  /// The GitHub account that publishes releases.
  public let owner: String
  /// The repository whose releases are checked.
  public let repository: String

  init?(owner: String, repository: String) {
    guard owner.wholeMatch(of: /[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?/) != nil,
      !owner.contains("--"),
      repository.wholeMatch(of: /[A-Za-z0-9._-]{1,100}/) != nil,
      repository != ".", repository != ".."
    else { return nil }
    self.owner = owner
    self.repository = repository
  }

  /**
   Reads the repository from a SpamWise bundle.

   - Parameter bundle: The app bundle to read.
   - Returns: `nil` when the bundle is not SpamWise, names no valid repository,
     or was installed from the Mac App Store.
   */
  public init?(bundle: Bundle = .main) {
    guard bundle.bundleIdentifier == Self.bundleIdentifier,
      let owner = bundle.object(forInfoDictionaryKey: Self.ownerKey) as? String,
      let repository = bundle.object(forInfoDictionaryKey: Self.repositoryKey) as? String
    else { return nil }
    let receipt = bundle.bundleURL.appending(path: Self.receiptPath)
    guard !FileManager.default.fileExists(atPath: receipt.path) else { return nil }
    self.init(owner: owner, repository: repository)
  }
}
