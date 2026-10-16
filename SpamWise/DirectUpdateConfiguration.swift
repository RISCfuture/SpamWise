import Foundation

struct DirectUpdateConfiguration: Equatable {
  let owner: String
  let repository: String
  let releasesURL: URL

  init?(owner: String, repository: String) {
    guard owner.wholeMatch(of: /[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?/) != nil,
      !owner.contains("--"),
      repository.wholeMatch(of: /[A-Za-z0-9._-]{1,100}/) != nil,
      repository != ".", repository != "..",
      let releasesURL = URL(string: "https://github.com/\(owner)/\(repository)/releases")
    else { return nil }
    self.owner = owner
    self.repository = repository
    self.releasesURL = releasesURL
  }

  init?(bundle: Bundle = .main) {
    guard bundle.object(forInfoDictionaryKey: "SpamWiseDistribution") as? String == "direct",
      bundle.bundleIdentifier == "codes.tim.SpamWise",
      let owner = bundle.object(forInfoDictionaryKey: "SpamWiseUpdateOwner") as? String,
      let repository = bundle.object(forInfoDictionaryKey: "SpamWiseUpdateRepository") as? String
    else { return nil }
    let receipt = bundle.bundleURL.appending(path: "Contents/_MASReceipt/receipt")
    guard !FileManager.default.fileExists(atPath: receipt.path) else { return nil }
    self.init(owner: owner, repository: repository)
  }
}
