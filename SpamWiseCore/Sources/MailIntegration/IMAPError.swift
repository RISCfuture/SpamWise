public import Foundation
import NIOCore
import NIOIMAP

/// Failures while configuring or communicating with an IMAP server.
public protocol IMAPOperationError: Error {}

/// Failures from the bounded IMAP connection; server text and credentials are never included.
public enum IMAPError: String, IMAPOperationError, LocalizedError, Sendable {
  case invalidConfiguration, unavailable, authenticationFailed, malformedResponse, limitExceeded
  case unsupported, rejected, deadlineExceeded
  /// A non-sensitive category suitable for presentation.
  public var errorDescription: String? {
    String(localized: "Couldn’t complete the IMAP operation.")
  }
  /// The connection or protocol failure, without server text or credentials.
  public var failureReason: String? {
    switch self {
      case .invalidConfiguration: String(localized: "The IMAP configuration is invalid.")
      case .unavailable: String(localized: "The IMAP connection is unavailable.")
      case .authenticationFailed: String(localized: "IMAP authentication failed.")
      case .malformedResponse: String(localized: "The IMAP server returned an invalid response.")
      case .limitExceeded:
        String(localized: "The IMAP response exceeds the supported resource limits.")
      case .unsupported: String(localized: "The IMAP server does not support this operation.")
      case .rejected: String(localized: "The IMAP server rejected the operation.")
      case .deadlineExceeded: String(localized: "The IMAP operation timed out.")
    }
  }

  /// Classifies a connection-pipeline failure without retaining server bytes.
  init(connectionFailure error: any Error) {
    switch error {
      case let error as Self: self = error
      case let error as IMAPDecoderError: self = Self(parserFailure: error.parserError)
      case is ByteToMessageDecoderError.PayloadTooLargeError: self = .limitExceeded
      case is UnexpectedResponse: self = .malformedResponse
      default: self = .unavailable
    }
  }

  private init(parserFailure error: any Error) {
    switch error {
      case is ExceededMaximumBodySizeError, is ExceededMaximumMessageAttributesError,
        is ExceededLiteralSizeLimitError, is TooMuchRecursion:
        self = .limitExceeded
      default: self = .malformedResponse
    }
  }
}
