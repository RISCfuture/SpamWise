import Foundation
import SpamWiseCore

/// What Mail reported after one change request.
enum MailChange: Equatable {
  /// Mail confirmed the change.
  case applied
  /// The message already showed the requested Review annotation, which stays the user's.
  case alreadyApplied
  /// Mail didn't confirm the change, which it may still apply.
  case unconfirmed
}

extension MailCommand {
  /// The command that applies the Review annotation this command applies or removes; nil for
  /// moves, read status and opening.
  var reviewAnnotation: Self? {
    switch self {
      case .orangeFlag, .clearOrangeFlag: .orangeFlag
      case .orangeBackground, .clearOrangeBackground: .orangeBackground
      case .moveToJunk, .moveToInbox, .markRead, .open: nil
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

  /// Whether SpamWise recorded setting the Review annotation that `command` removes.
  func setReview(removedBy command: MailCommand, on identity: MessageIdentity) async -> Bool {
    guard let annotation = command.reviewAnnotation, let reviewMarks else { return false }
    let marks = try? await reviewMarks.read(Self.reviewMarksKey, default: [String]())
    return marks?.contains(Self.reviewMark(annotation, for: identity)) ?? false
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
