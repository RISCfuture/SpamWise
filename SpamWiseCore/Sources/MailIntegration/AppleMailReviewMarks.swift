import Foundation
import SpamWiseCore

/// What Mail reported after one change request.
enum MailChange: Equatable {
  /// Mail confirmed the change.
  case applied
  /// The message already shows the requested state. A Review annotation then stays the user's,
  /// because SpamWise didn't see that it set it.
  case alreadyApplied
  /// Mail reported that the message doesn't show the change yet; it may still apply it.
  case unconfirmed
  /// Mail didn't reply in time or the request was cancelled, so it may still apply the change,
  /// or may have found the annotation already there.
  case unanswered
}

extension MailCommand {
  /// The command that applies the Review annotation this command applies or removes; nil for
  /// moves, read status, the junk mark and opening.
  var reviewAnnotation: Self? {
    switch self {
      case .orangeFlag, .clearOrangeFlag: .orangeFlag
      case .orangeBackground, .clearOrangeBackground: .orangeBackground
      case .moveToJunk, .moveToInbox, .markRead, .clearJunkMark, .open: nil
    }
  }
  /// Whether this command removes a Review annotation.
  var removesReview: Bool { self == .clearOrangeFlag || self == .clearOrangeBackground }
}

extension AppleMailAdapter {
  private static let reviewMarksKey = "apple-mail-review-marks-v1"
  private static let maximumReviewMarks = 1000

  private static func reviewMark(_ annotation: MailCommand, for identity: MessageIdentity)
    -> String
  {
    annotation.rawValue + ":" + identity.key
  }

  /**
   Whether SpamWise recorded setting the Review annotation that `command` removes; false without
   a store.

   - Throws: The store's error when the recorded marks can't be read.
   */
  func hasRecordedReview(removedBy command: MailCommand, on identity: MessageIdentity) async throws
    -> Bool
  {
    guard let annotation = command.reviewAnnotation, let reviewMarks else { return false }
    return try await reviewMarks.read(Self.reviewMarksKey, default: [String]())
      .contains(Self.reviewMark(annotation, for: identity))
  }

  /// Records a Review annotation SpamWise set, or forgets one it removed, once Mail confirms it.
  func record(_ change: MailChange, of command: MailCommand, on identity: MessageIdentity) async {
    guard change == .applied, let annotation = command.reviewAnnotation, let reviewMarks else {
      return
    }
    let mark = Self.reviewMark(annotation, for: identity), adds = !command.removesReview
    try? await reviewMarks.update(Self.reviewMarksKey, default: [String]()) { marks in
      marks.removeAll { $0 == mark }
      guard adds else { return }
      marks.append(mark)
      marks.removeFirst(max(0, marks.count - Self.maximumReviewMarks))
    }
  }
}
