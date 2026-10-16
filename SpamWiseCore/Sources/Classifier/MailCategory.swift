import Foundation

/// What kind of mail a message is, independent of whether this user wants it.
public enum MailCategory: String, Codable, CodingKeyRepresentable, Sendable, CaseIterable {
  /// Correspondence written by a person to the user.
  case personal
  /// Receipts, shipping, bills, bookings, appointments, support replies and account or security notices.
  case transactional
  /// Clubs, groups, schools, buildings and organizations the user belongs to.
  case community
  /// Sales, discounts, product launches and other mail whose main purpose is to sell.
  case promotion
  /// Reminders about an unfinished cart, checkout or booking.
  case abandonedCart = "abandonedCart"
  /// Editorial content, digests and articles.
  case newsletter
  /// Product news, changelogs and feature announcements from services.
  case productUpdate = "productUpdate"
  /// Concerts, tickets, webinars, conferences and other event marketing.
  case event
  /// Activity notifications and suggestions from social networks.
  case socialNotification = "socialNotification"
  /// Requests for reviews, ratings, feedback or survey answers.
  case survey
  /// Card, loan, credit, insurance and other financial offers.
  case financialOffer = "financialOffer"
  /// Donation, membership drive and political fundraising appeals.
  case fundraising
  /// Unsolicited business pitches, press releases and sales outreach.
  case coldOutreach = "coldOutreach"
  /// Unsolicited bulk mail from no legitimate sender.
  case spam
  /// Phishing, fraud, extortion or malware delivery.
  case scam
  /// The model did not name a category, as in records from earlier versions.
  case unknown

  /// Legitimate bulk mail whose value depends on the recipient, in the order setup presents it.
  public static let graymail: [Self] = [
    .promotion, .abandonedCart, .newsletter, .productUpdate, .event, .socialNotification,
    .survey, .financialOffer, .fundraising, .coldOutreach, .community
  ]

  /// Whether this user's preference decides how this kind of mail is handled.
  public var isGraymail: Bool { Self.graymail.contains(self) }

  /// The category's name in the user's language.
  public var localizedName: String {
    switch self {
      case .personal: String(localized: "Personal mail", bundle: .module)
      case .transactional: String(localized: "Receipts and account notices", bundle: .module)
      case .community: String(localized: "Clubs and groups", bundle: .module)
      case .promotion: String(localized: "Store promotions", bundle: .module)
      case .abandonedCart: String(localized: "Cart reminders", bundle: .module)
      case .newsletter: String(localized: "Newsletters", bundle: .module)
      case .productUpdate: String(localized: "Product news", bundle: .module)
      case .event: String(localized: "Event and ticket offers", bundle: .module)
      case .socialNotification: String(localized: "Social network notifications", bundle: .module)
      case .survey: String(localized: "Surveys and review requests", bundle: .module)
      case .financialOffer: String(localized: "Card and loan offers", bundle: .module)
      case .fundraising: String(localized: "Fundraising", bundle: .module)
      case .coldOutreach: String(localized: "Sales pitches", bundle: .module)
      case .spam: String(localized: "Spam", bundle: .module)
      case .scam: String(localized: "Scams and phishing", bundle: .module)
      case .unknown: String(localized: "Uncategorized", bundle: .module)
    }
  }

  /// A short description of typical messages, shown beside a graymail preference.
  public var localizedExample: String {
    switch self {
      case .community:
        String(localized: "Meetings, events and updates from groups you belong to", bundle: .module)
      case .promotion: String(localized: "Sales, discounts and new arrivals", bundle: .module)
      case .abandonedCart:
        String(localized: "“You left something in your cart”", bundle: .module)
      case .newsletter: String(localized: "Articles, digests and editorial mail", bundle: .module)
      case .productUpdate:
        String(localized: "What’s new and changelogs from apps and services", bundle: .module)
      case .event:
        String(localized: "Concert, ticket, webinar and conference offers", bundle: .module)
      case .socialNotification:
        String(localized: "Posts, suggestions and activity from social networks", bundle: .module)
      case .survey: String(localized: "“How did we do?” and rating requests", bundle: .module)
      case .financialOffer:
        String(localized: "Pre-approvals, credit cards, loans and points offers", bundle: .module)
      case .fundraising:
        String(localized: "Donation, annual fund and political appeals", bundle: .module)
      case .coldOutreach:
        String(localized: "Unsolicited business pitches and press releases", bundle: .module)
      case .personal, .transactional, .spam, .scam, .unknown: localizedName
    }
  }

  /// Decodes an unrecognized category as ``unknown``.
  public init(from decoder: any Decoder) throws {
    self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
  }
}

/// How the user wants one kind of graymail handled.
public enum GraymailPreference: String, Codable, Sendable, CaseIterable {
  /// Leave it in Inbox without a Review annotation.
  case keep
  /// Leave it in Inbox and annotate it for Review.
  case review
  /// Move it to Junk when the classifier is confident enough for the filtering strength.
  case junk
}

/// The user's preference for each kind of graymail.
public struct CategoryPreferences: Codable, Sendable, Equatable {
  /// First-run preferences: unfamiliar selling is flagged for Review and informational mail kept.
  public static let defaults = Self(
    [
      .promotion: .review, .abandonedCart: .review, .financialOffer: .review,
      .fundraising: .review, .coldOutreach: .review
    ]
  )

  private var choices: [MailCategory: GraymailPreference]

  /// Every graymail category's preference, in presentation order.
  public var all: [(category: MailCategory, preference: GraymailPreference)] {
    MailCategory.graymail.map { ($0, choices[$0] ?? .keep) }
  }

  /// Creates preferences from explicit choices; graymail categories without one are kept.
  public init(_ choices: [MailCategory: GraymailPreference] = [:]) {
    self.choices = Dictionary(
      uniqueKeysWithValues: MailCategory.graymail.map { ($0, choices[$0] ?? .keep) }
    )
  }

  /// Decodes stored choices, ignoring categories and preferences this version does not recognize.
  public init(from decoder: any Decoder) throws {
    let raw = try decoder.singleValueContainer().decode([String: String].self)
    self.init(
      Dictionary(
        uniqueKeysWithValues: raw.compactMap { key, value in
          MailCategory(rawValue: key).flatMap { category in
            GraymailPreference(rawValue: value).map { (category, $0) }
          }
        }
      )
    )
  }

  /// Encodes each graymail category's preference by raw value.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(
      Dictionary(uniqueKeysWithValues: choices.map { ($0.key.rawValue, $0.value.rawValue) })
    )
  }

  /// The preference for a graymail category, or nil for categories no preference applies to.
  public subscript(category: MailCategory) -> GraymailPreference? {
    get { choices[category] }
    set {
      guard category.isGraymail else { return }
      choices[category] = newValue
    }
  }
}
