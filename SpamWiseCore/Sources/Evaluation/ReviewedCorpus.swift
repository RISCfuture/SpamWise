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
public enum ReviewedCorpusError: CorpusEvaluationError, Sendable, LocalizedError {
  case duplicateContent, oversized
  /// Non-sensitive input failure explanation.
  public var errorDescription: String? {
    String(localized: "Couldn’t evaluate the reviewed corpus.")
  }
  /// The input condition that prevents a valid evaluation.
  public var failureReason: String? {
    switch self {
      case .duplicateContent: String(localized: "The reviewed corpus contains duplicate content.")
      case .oversized: String(localized: "The reviewed export exceeds the supported input limits.")
    }
  }
  /// An available correction to the supplied corpus.
  public var recoverySuggestion: String? {
    switch self {
      case .duplicateContent: String(localized: "Remove duplicate content before evaluation.")
      case .oversized: nil
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

  /// Validates all retained content identities before selecting a statistical partition.
  public init(labels: [ReviewedLabel], partition: ReviewedCorpusPartition = .heldOut) throws {
    guard labels.count <= Self.maximumLabels else { throw ReviewedCorpusError.oversized }
    var entries: [Entry] = [], identities: Set<String> = [], missing = 0, excluded = 0
    for label in labels {
      guard let message = label.message else { missing += 1; continue }
      guard try JSONEncoder().encode(message).count <= Self.maximumMessageBytes else {
        throw ReviewedCorpusError.oversized
      }
      let identity = LearningSample.identity(for: message)
      guard identities.insert(identity).inserted else { throw ReviewedCorpusError.duplicateContent }
      let heldOut = LearningSample.partition(for: identity) == .heldOut
      guard partition == .all || (partition == .heldOut) == heldOut else { excluded += 1; continue }
      let truth: EvaluationTruth
      switch label.label {
        case .inbox: truth = .good
        case .junk: truth = .junk
        case .review: truth = .graymail
      }
      entries.append(.init(id: identity, message: message, truth: truth))
    }
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
    let properties = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
    guard properties.isRegularFile == true,
      (properties.fileSize ?? Int.max) <= Self.maximumExportBytes
    else {
      throw ReviewedCorpusError.oversized
    }
    let data = try Data(contentsOf: url)
    guard data.count <= Self.maximumExportBytes else { throw ReviewedCorpusError.oversized }
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
