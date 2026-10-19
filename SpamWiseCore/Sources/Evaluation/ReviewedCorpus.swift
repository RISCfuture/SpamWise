public import Foundation
public import SpamWiseCore

/// Which independently reviewed content split to evaluate.
public enum ReviewedCorpusPartition: String, Codable, Sendable {
  case heldOut = "held-out"
  case training, all
}

/// Failures that prevent a corpus from being evaluated.
public protocol CorpusEvaluationError: Error {}

/// Invalid reviewed-corpus input that must be resolved before model calls.
public enum ReviewedCorpusError: CorpusEvaluationError, BoundedInputError, Sendable, Equatable,
  LocalizedError
{
  /// The same content carries different labels; the associated values are the sample identities.
  case conflictingLabels([String])
  /// The export holds more labels than one evaluation accepts.
  case tooManyLabels(count: Int, limit: Int)
  /// One retained message is larger than the parser budget.
  case messageTooLarge(sampleID: String, limit: Int)
  /// The export file is larger than one evaluation accepts.
  case fileTooLarge(URL, limit: Int)
  /// The export path names a directory or other non-regular file, after resolving links.
  case notRegularFile(URL)
  /// Non-sensitive input failure explanation.
  public var errorDescription: String? {
    String(localized: "Couldn’t evaluate the reviewed corpus.", bundle: .module)
  }
  /// The input condition that prevents a valid evaluation.
  public var failureReason: String? {
    switch self {
      case .conflictingLabels(let samples):
        String(
          localized:
            "The reviewed corpus labels the same content differently: \(samples.formatted(.list(type: .and))).",
          bundle: .module
        )
      case let .tooManyLabels(count, limit):
        String(
          localized:
            "The export has \(count) labels; at most \(limit) are supported.",
          bundle: .module
        )
      case let .messageTooLarge(sampleID, limit):
        String(
          localized:
            "Sample \(sampleID) exceeds the \(limit.formatted(.byteCount(style: .file))) message limit.",
          bundle: .module
        )
      case let .fileTooLarge(url, limit):
        String(
          localized:
            "\(url.path) exceeds the \(limit.formatted(.byteCount(style: .file))) export limit.",
          bundle: .module
        )
      case .notRegularFile(let url):
        String(localized: "\(url.path) isn’t a regular file.", bundle: .module)
    }
  }
  /// An available correction to the supplied corpus.
  public var recoverySuggestion: String? {
    switch self {
      case .conflictingLabels:
        String(
          localized: "Relabel or forget the conflicting examples, then export again.",
          bundle: .module
        )
      case .tooManyLabels, .fileTooLarge:
        String(localized: "Split the export into smaller files.", bundle: .module)
      case .messageTooLarge: nil
      case .notRegularFile:
        String(localized: "Pass the exported labels JSON file itself.", bundle: .module)
    }
  }
}

/// Selected retained messages and explicit accounting for skipped metadata-only labels.
public struct ReviewedCorpus: Sendable {
  private static let maximumLabels = 10_000
  private static let maximumMessageBytes = 2_000_000
  /// Total JSON bytes accepted from one export.
  public static let maximumExportBytes = 64 * 1024 * 1024
  /// Parsed retained messages, never synthesized MIME.
  public let entries: [Entry]
  /// Selection and missing-content counts for reports.
  public let summary: Summary

  /**
   Validates all retained content identities before selecting a statistical partition.

   Repeated content with the same label counts once.

   - Throws: ``ReviewedCorpusError/conflictingLabels(_:)`` when repeated content carries
     different labels.
   */
  public init(labels: [ReviewedLabel], partition: ReviewedCorpusPartition = .heldOut) throws {
    guard labels.count <= Self.maximumLabels else {
      throw ReviewedCorpusError.tooManyLabels(count: labels.count, limit: Self.maximumLabels)
    }
    var entries: [Entry] = [], truths: [String: MailLabel] = [:], conflicts: Set<String> = []
    var missing = 0, excluded = 0
    for label in labels {
      guard let message = label.message else { missing += 1; continue }
      let identity = LearningSample.identity(for: message)
      guard try JSONEncoder().encode(message).count <= Self.maximumMessageBytes else {
        throw ReviewedCorpusError.messageTooLarge(
          sampleID: identity,
          limit: Self.maximumMessageBytes
        )
      }
      if let seen = truths.updateValue(label.label, forKey: identity) {
        if seen != label.label { conflicts.insert(identity) }
        continue
      }
      let split = LearningSample.partition(for: identity)
      guard partition == .all || (partition == .heldOut) == (split == .heldOut) else {
        excluded += 1; continue
      }
      let truth: EvaluationTruth
      switch label.label {
        case .inbox: truth = .good
        case .junk: truth = .junk
        case .review: truth = .graymail
      }
      entries.append(.init(id: identity, message: message, truth: truth, partition: split))
    }
    guard conflicts.isEmpty else { throw ReviewedCorpusError.conflictingLabels(conflicts.sorted()) }
    self.entries = entries.sorted { $0.id < $1.id }
    summary = .init(
      totalLabels: labels.count,
      missingContent: missing,
      excludedPartition: excluded,
      selected: entries.count,
      partition: partition
    )
  }

  /// Loads a bounded exported label array without consulting the application's state.
  public init(url: URL, partition: ReviewedCorpusPartition = .heldOut) throws {
    let data = try ReviewedCorpusError.boundedContents(of: url, limit: Self.maximumExportBytes)
    try self.init(
      labels: JSONDecoder().decode([ReviewedLabel].self, from: data),
      partition: partition
    )
  }

  /// One independently labeled retained message; truth is never included in the model input.
  public struct Entry: Sendable {
    /// Content identity independent of delivery headers and label.
    public let id: String
    /// Retained parsed message supplied to the pipeline.
    public let message: ParsedMessage
    /// Human label used only when constructing metrics.
    public let truth: EvaluationTruth
    /// Statistical split derived from the content identity.
    public let partition: LearningPartition
  }

  /// Explicit counts for selected, missing and excluded entries.
  public struct Summary: Codable, Sendable {
    /// Number of label entries in the input export.
    public let totalLabels: Int
    /// Entries without retained parsed message content, across the whole export.
    public let missingContent: Int
    /// Retained entries excluded by the selected partition.
    public let excludedPartition: Int
    /// Retained entries actually selected for evaluation.
    public let selected: Int
    /// Requested statistical partition.
    public let partition: ReviewedCorpusPartition
  }
}
