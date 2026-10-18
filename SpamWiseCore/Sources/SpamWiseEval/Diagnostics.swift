import ArgumentParser
import Evaluation
import Foundation
import SpamWiseCore

/// A labeled run that can't produce trustworthy metrics; no Mail action is ever requested.
enum CorpusRunError: CorpusEvaluationError, LocalizedError {
  /// The corpus has no labeled `.eml` files.
  case emptyCorpus(URL)
  /// Two corpus files contain identical bytes.
  case duplicateMessage(file: String, original: String)
  /// A corpus path names a directory or other non-regular file, after resolving links.
  case notRegularFile(String)
  /// A corpus file is larger than the parser accepts.
  case messageTooLarge(file: String, limit: Int)
  /// The mock responses have no verdict for this raw-message hash.
  case missingMock(hash: String)
  /// The live-call authorization variable isn't set.
  case liveDisabled(variable: String)
  /// The selected provider's API key variable is empty or unset.
  case missingKey(variable: String)
  /// Evaluation stopped because a message couldn't be evaluated as the cohort requires.
  case stopped(file: String, cause: String)

  var errorDescription: String? {
    String(localized: "Couldn’t evaluate the corpus.", bundle: .module)
  }
  var failureReason: String? {
    switch self {
      case .emptyCorpus(let url):
        String(
          localized: "\(url.path) has no .eml files in good/, junk/ or graymail/.",
          bundle: .module
        )
      case let .duplicateMessage(file, original):
        String(localized: "\(file) has the same bytes as \(original).", bundle: .module)
      case .notRegularFile(let file):
        String(localized: "\(file) isn’t a regular file.", bundle: .module)
      case let .messageTooLarge(file, limit):
        String(
          localized:
            "\(file) exceeds the \(limit.formatted(.byteCount(style: .file))) parser limit.",
          bundle: .module
        )
      case .missingMock(let hash):
        String(localized: "No mock response exists for hash \(hash).", bundle: .module)
      case .liveDisabled(let variable):
        String(
          localized: "Live evaluation requires \(variable)=1. No provider call was made.",
          bundle: .module
        )
      case .missingKey(let variable):
        String(
          localized: "\(variable) isn’t set for this process. The CLI never saves keys.",
          bundle: .module
        )
      case let .stopped(file, cause):
        String(localized: "Stopped at \(file): \(cause)", bundle: .module)
    }
  }
  var recoverySuggestion: String? {
    switch self {
      case .duplicateMessage:
        String(localized: "Remove duplicates before calibration.", bundle: .module)
      case .stopped:
        String(
          localized:
            "No report was written, because its metrics would cover only part of the corpus.",
          bundle: .module
        )
      default: nil
    }
  }
}

/// Prints failures with their category, reason and recovery, then exits nonzero.
enum Diagnostics {
  /// Runs `body`, reporting any failure other than an argument-parser exit on standard error.
  static func reporting(_ body: () async throws -> Void) async throws {
    do { try await body() } catch let error where error is ValidationError || error is ExitCode {
      throw error
    } catch {
      FileHandle.standardError.write(Data((describe(error) + "\n").utf8))
      throw ExitCode.failure
    }
  }

  /// One-line explanation of `error`, naming the JSON location of a decoding failure.
  static func describe(_ error: any Error) -> String {
    switch error {
      case let error as DecodingError: describe(error)
      case let error as any LocalizedError:
        [error.errorDescription, error.failureReason, error.recoverySuggestion]
          .compactMap { $0 }.joined(separator: " ")
      default: error.localizedDescription
    }
  }

  private static func describe(_ error: DecodingError) -> String {
    let context: DecodingError.Context
    switch error {
      case .typeMismatch(_, let found), .valueNotFound(_, let found), .keyNotFound(_, let found),
        .dataCorrupted(let found):
        context = found
      @unknown default: return error.localizedDescription
    }
    let path = context.codingPath.map { key in
      key.intValue.map { "[\($0)]" } ?? "." + key.stringValue
    }.joined()
    let location = path.isEmpty ? String(localized: "the top level", bundle: .module) : path
    return String(
      localized: "The JSON input is invalid at \(location): \(context.debugDescription)",
      bundle: .module
    )
  }
}
