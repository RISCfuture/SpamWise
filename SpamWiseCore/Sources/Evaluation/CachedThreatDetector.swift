public import Foundation
public import SpamWiseCore

/// Caches independent findings by effective content, account, evidence and complete detector identity.
public actor CachedThreatDetector: ThreatDetector {
  /// The underlying inference identity, including its network requirement.
  public nonisolated let identity: ThreatDetectorIdentity
  private let directory: URL
  private let underlying: any ThreatDetector
  /// Valid responses reused without inference.
  public private(set) var hits = 0

  /// Creates a private local cache for an explicitly selected detector.
  public init(directory: URL, underlying: any ThreatDetector) throws {
    self.directory = directory; self.underlying = underlying; identity = underlying.identity
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
  }

  /// Revalidates cached findings; wholly unknown responses are not cached.
  public func assess(_ input: ThreatInput) async throws -> [ThreatFinding] {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let fingerprint = try input.fingerprint()
    let key = stableHash(
      try encoder.encode(
        CacheIdentity(
          input: fingerprint,
          detector: identity,
          schema: ThreatAssessment.schemaID
        )
      )
    )
    let url = directory.appending(path: key + ".json")
    if let data = try? Data(contentsOf: url),
      let cached = try? JSONDecoder().decode(ThreatAssessment.self, from: data),
      cached.inputFingerprint == fingerprint, cached.detector == identity,
      (try? cached.validate()) != nil,
      cached.findings.contains(where: { $0.status != .unknown })
    {
      hits += 1
      return cached.findings
    }
    let findings = try await underlying.assess(input)
    let assessment = try ThreatAssessment(input: input, detector: identity, findings: findings)
    if assessment.findings.contains(where: { $0.status != .unknown }) {
      try encoder.encode(assessment).write(to: url, options: .atomic)
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    return assessment.findings
  }

  private struct CacheIdentity: Encodable {
    var input: String
    var detector: ThreatDetectorIdentity
    var schema: String
  }
}
