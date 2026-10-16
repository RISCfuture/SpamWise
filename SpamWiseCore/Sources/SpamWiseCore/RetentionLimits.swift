public import Foundation

/// The single definition of every bound on retained state, shared by writes and backup validation.
public enum RetentionLimits {
  /// Activity records kept for display and duplicate detection.
  public static let activityRecords = 5000
  /// Configuration and learning audit events.
  public static let auditEvents = 1000
  /// Quoted correction examples.
  public static let corrections = 200
  /// Explicit reviewed labels.
  public static let reviewedLabels = 500
  /// Queued classification retries.
  public static let retries = 100
  /// Explicit sender rules.
  public static let senderRules = 10_000
  /// User-authored content rules.
  public static let contentRules = 100
  /// Characters of filtering policy text.
  public static let policyCharacters = 8000
  /// Characters of message text kept for reviewed labels and retries.
  public static let messageCharacters = 16_000
  /// URLs kept from one retained message.
  public static let messageURLs = 40
  /// Characters kept from one retained URL.
  public static let urlCharacters = 2048
  /// Training-folder identities observed during one unfinished sweep.
  public static let trainingObservations = 5000
  /// History import identities remembered per account for deduplication.
  public static let historyImportIdentities = 10_000
  /// Messages sampled per account to detect its receiving servers' authserv-ids.
  public static let authServerObservationMessages = 50
  /// Distinct receiving-server authserv-ids counted per account during detection.
  public static let authServerObservationServers = 16
  /**
   Age after which an action claim is pruned.

   A claim is the only record that an action was requested for a message identity, and the
   identity covers the account, Message-ID and full content hash. Within this window SpamWise
   never requests a second automatic action for the same message, even after its Activity record
   has been pruned. Mail that is still resolvable after the window is classified again. An
   explicit Good correction leaves an Allow rule that keeps a rescued message in the Inbox before
   any model decision when trusted authentication confirms its sender; for an unconfirmed sender
   the rule reaches the classifier only as evidence. Thirteen months covers a full year of
   repeated Inbox sweeps, plus a month of margin, with claims stored as indexed rows that are
   fetched by key and never decoded in bulk.
   */
  public static let actionClaimAge: TimeInterval = 400 * 86_400
}

extension ParsedMessage {
  /// A copy limited to the retained text and URL bounds, without headers unless kept.
  public func boundedForRetention(keepingHeaders: Bool = false) -> ParsedMessage {
    var bounded = self
    bounded.text = String(text.prefix(RetentionLimits.messageCharacters))
    bounded.urls = urls.prefix(RetentionLimits.messageURLs).map {
      String($0.prefix(RetentionLimits.urlCharacters))
    }
    if !keepingHeaders { bounded.headers = [:] }
    return bounded
  }
}
