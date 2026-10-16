import Foundation
import SpamWiseCore

extension ModelBackend {
  var localizedTitle: String {
    switch self {
      case .claude: String(localized: "Claude")
      case .onDevice: String(localized: "Apple on-device")
      case .privateCloudCompute: String(localized: "Private Cloud Compute")
      case .openAI: String(localized: "OpenAI")
      case .gemini: String(localized: "Gemini")
    }
  }
}

extension MailTransport {
  var localizedTitle: String {
    switch self {
      case .appleMail: String(localized: "Apple Mail")
      case .imap: String(localized: "IMAP")
    }
  }
}

extension FilteringStrength {
  var localizedTitle: String {
    switch self {
      case .conservative: String(localized: "Conservative")
      case .balanced: String(localized: "Balanced")
      case .aggressive: String(localized: "Aggressive")
    }
  }
}

extension MailLabel {
  var localizedTitle: String {
    switch self {
      case .inbox: String(localized: "Inbox")
      case .review: String(localized: "Review")
      case .junk: String(localized: "Junk")
    }
  }
}

extension MailAction {
  var localizedTitle: String {
    switch self {
      case .none: String(localized: "No action")
      case .orangeFlag: String(localized: "Orange flag")
      case .orangeBackground: String(localized: "Orange background")
      case .moveToJunk: String(localized: "Move to Junk")
      case .moveToInbox: String(localized: "Move to Inbox")
    }
  }
}

extension ActionOutcome {
  var localizedTitle: String {
    switch self {
      case .noAction: String(localized: "No action")
      case .dryRun: String(localized: "Dry run")
      case .paused: String(localized: "Paused")
      case .pending: String(localized: "Pending")
      case .requested: String(localized: "Requested")
      case .applied: String(localized: "Applied")
      case .failed: String(localized: "Failed")
      case .unclassified: String(localized: "Unclassified")
      case .superseded: String(localized: "Superseded")
      case .duplicate: String(localized: "Duplicate")
      case .integrationUnavailable: String(localized: "Integration unavailable")
    }
  }
}

extension RuleScope {
  var localizedTitle: String {
    switch self {
      case .address: String(localized: "Email address")
      case .domain: String(localized: "Entire domain")
    }
  }
}

extension RuleDisposition {
  var localizedTitle: String {
    switch self {
      case .allow: String(localized: "Allow")
      case .block: String(localized: "Block")
    }
  }
}

extension IncomingRoute {
  var localizedTitle: String {
    switch self {
      case .unverified: String(localized: "Not verified")
      case .mailKit: String(localized: "MailKit")
      case .mailRule: String(localized: "Mail rule")
      case .imap: String(localized: "IMAP")
    }
  }
}

extension Help {
  static func localizedTitle(for page: String) -> String {
    switch page {
      case "getting-started": String(localized: "Getting started")
      case "how-decisions-are-made": String(localized: "How decisions are made")
      case "what-data-is-sent": String(localized: "What data is sent")
      case "correcting-mistakes": String(localized: "Correcting mistakes")
      case "filtering-strength": String(localized: "Filtering strength")
      case "troubleshooting-mail-integration": String(localized: "Troubleshooting Mail integration")
      default: String(localized: "SpamWise Help")
    }
  }
}
