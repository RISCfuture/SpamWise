/// Mail providers whose registrable domain is shared by unrelated people.
///
/// A sender at one of these domains says nothing about any other sender there, so domain-wide
/// trust, receipt history and domain rule suggestions never apply to them.
public enum SharedMailboxDomains {
  /// Freemail, ISP, relay, group and newsletter-platform domains. Relays such as Hide My Email
  /// (`privaterelay.appleid.com`), mailing-list hosts and newsletter platforms deliver mail from
  /// unrelated people under one registrable domain.
  private static let domains: Set<String> = [
    "126.com", "163.com", "33mail.com", "addy.io", "aim.com", "aleeas.com", "aliceadsl.fr",
    "aliyun.com", "anonaddy.com", "anonaddy.me", "aol.com", "appleid.com", "att.net",
    "bellsouth.net", "bigpond.com", "bigpond.net.au", "bk.ru", "bol.com.br", "btinternet.com",
    "charter.net", "club-internet.fr", "comcast.net", "cox.net", "daum.net", "disroot.org",
    "duck.com", "earthlink.net", "email.com", "fastmail.com", "fastmail.fm", "foxmail.com",
    "free.fr", "gmail.com", "googlegroups.com", "googlemail.com", "groups.io", "hanmail.net",
    "hey.com", "hushmail.com", "icloud.com", "inbox.ru", "interia.pl", "laposte.net", "libero.it",
    "list.ru", "mac.com", "mail.com", "mail.ru", "mailbox.org", "mailfence.com", "me.com",
    "movistar.es", "mozmail.com", "msn.com", "naver.com", "neuf.fr", "numericable.fr", "o2.pl",
    "onet.pl", "ono.com", "optonline.net", "orange.fr", "passinbox.com", "passmail.net",
    "passport.com", "pm.me", "posteo.de", "posteo.net", "proton.me", "protonmail.ch",
    "protonmail.com", "qq.com", "rambler.ru", "rediffmail.com", "riseup.net", "rocketmail.com",
    "rogers.com", "rr.com", "sbcglobal.net", "seznam.cz", "sfr.fr", "shaw.ca", "simplelogin.co",
    "simplelogin.com", "sina.com", "sky.com", "slmail.me", "sohu.com", "substack.com",
    "sympatico.ca", "t-online.de", "telefonica.net", "terra.com.br", "terra.es", "tiscali.it",
    "tuta.com", "tuta.io", "tutanota.com", "tutanota.de", "uol.com.br", "usa.com", "verizon.net",
    "virgilio.it", "virginmedia.com", "wanadoo.fr", "web.de", "wp.pl", "ya.ru", "yahoogroups.com",
    "yeah.net", "ymail.com", "zoho.com", "zohomail.com"
  ]
  /// Provider names registered under many country suffixes, such as `gmx.de` and `yahoo.co.jp`.
  private static let providerLabels: Set<String> = [
    "aol", "gmx", "hotmail", "live", "outlook", "yahoo", "yandex"
  ]

  /// Whether a registrable domain belongs to a shared mailbox provider.
  public static func contains(_ registrableDomain: String) -> Bool {
    let domain = registrableDomain.lowercased()
    guard !domains.contains(domain) else { return true }
    return domain.split(separator: ".").first.map { providerLabels.contains(String($0)) } ?? false
  }
}
