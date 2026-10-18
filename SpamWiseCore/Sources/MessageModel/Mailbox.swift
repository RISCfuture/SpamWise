import Foundation

/// One RFC 5322 mailbox: a validated address and an untrusted display phrase.
public struct Mailbox: Sendable, Equatable {
  private static let maximumAddressBytes = 254
  private static let addressPattern: String = {
    let atom = #"[A-Z0-9!#$%&'*+/=?^_`{|}~-]+"#
    let label = #"[A-Z0-9](?:[A-Z0-9-]*[A-Z0-9])?"#
    return "\\A" + atom + "(?:\\." + atom + ")*@" + label + "(?:\\." + label + ")*\\z"
  }()

  /// Normalized lowercase address taken from the angle-addr or bare addr-spec.
  public var address: String
  /**
   Display phrase with quoting and comments removed, still possibly RFC 2047 encoded.

   For a bare addr-spec, the comment text serves as the display phrase. The phrase is a
   sender claim and may itself contain an address that differs from ``address``.
   */
  public var displayName: String
  /// Comment text with nesting and escapes resolved; like the display phrase, a sender claim.
  public var comments: String

  /**
   Parses exactly one mailbox, accepting any display phrase before a single angle-addr.

   Empty list members, such as a trailing comma, are ignored. Returns nil for several
   mailboxes, multiple or unterminated angle-addrs, text after the angle-addr, quoted local
   parts and addresses that fail validation.
   */
  public init?(_ value: String) {
    let lexemes = MailboxScanner.members(of: value).map { member in
      var scanner = MailboxScanner(member)
      return scanner.mailbox()
    }
    let mailboxes = lexemes.filter { $0?.isEmpty != true }
    guard mailboxes.count == 1, let lexeme = mailboxes[0] else { return nil }
    if let angle = lexeme.angle {
      guard let address = Self.validated(angle) else { return nil }
      self.address = address
      displayName = lexeme.phrase.isEmpty ? lexeme.comments : lexeme.phrase
      comments = lexeme.comments
    } else {
      guard !lexeme.containsQuotedString, let address = Self.validated(lexeme.phrase) else {
        return nil
      }
      self.address = address
      displayName = lexeme.comments
      comments = lexeme.comments
    }
  }

  /// Parses a comma-separated address list, omitting members that are not single mailboxes.
  public static func list(_ value: String) -> [Self] {
    MailboxScanner.members(of: value).compactMap(Self.init)
  }

  private static func validated(_ candidate: String) -> String? {
    let trimmed = candidate.trimmingCharacters(in: .whitespaces)
    guard trimmed.utf8.count <= maximumAddressBytes,
      trimmed.range(of: addressPattern, options: [.regularExpression, .caseInsensitive]) != nil
    else { return nil }
    return trimmed.lowercased()
  }
}

/// Lexical pieces of one mailbox with quoting, escapes and comments resolved.
private struct MailboxLexeme {
  var phrase = ""
  var comments = ""
  var angle: String?
  var containsQuotedString = false

  /// Whether the member holds only whitespace and comments, as an obsolete empty list member.
  var isEmpty: Bool { phrase.isEmpty && angle == nil && !containsQuotedString }
}

/// Single-pass RFC 5322 lexer for quoted strings, nested comments and angle-addrs.
private struct MailboxScanner {
  private let characters: [Character]
  private var index = 0

  init(_ value: String) { characters = Array(value) }

  /// Splits an address list at commas outside quotes, comments and angle brackets.
  static func members(of value: String) -> [String] {
    var members: [String] = [], current = "", quoted = false, escaped = false
    var commentDepth = 0, inAngle = false
    for character in value {
      if character == ",", !quoted, commentDepth == 0, !inAngle {
        members.append(current); current = ""; continue
      }
      current.append(character)
      if escaped { escaped = false; continue }
      switch character {
        case "\\" where quoted || commentDepth > 0: escaped = true
        case "\"" where commentDepth == 0: quoted.toggle()
        case "(" where !quoted: commentDepth += 1
        case ")" where !quoted && commentDepth > 0: commentDepth -= 1
        case "<" where !quoted && commentDepth == 0: inAngle = true
        case ">" where !quoted && commentDepth == 0: inAngle = false
        default: break
      }
    }
    return members + [current]
  }

  /// Treats only ASCII whitespace as folding, since raw 8-bit header bytes appear as Latin-1.
  private static func isFoldingWhitespace(_ character: Character) -> Bool {
    character.isASCII && character.isWhitespace
  }

  private static func collapsed(_ text: String) -> String {
    text.split(whereSeparator: isFoldingWhitespace).joined(separator: " ")
  }

  mutating func mailbox() -> MailboxLexeme? {
    var lexeme = MailboxLexeme(), phrase = "", trailing = "", comments: [String] = []
    while index < characters.count {
      let character = characters[index]
      index += 1
      switch character {
        case "\"":
          guard lexeme.angle == nil, let quoted = quotedString() else { return nil }
          phrase += quoted; lexeme.containsQuotedString = true
        case "(":
          guard let comment = comment() else { return nil }
          comments.append(comment)
          phrase += " "
        case "<":
          guard lexeme.angle == nil, let angle = angleAddress() else { return nil }
          lexeme.angle = angle
        case ">", ",":
          return nil
        default:
          if lexeme.angle == nil { phrase.append(character) } else { trailing.append(character) }
      }
    }
    guard trailing.allSatisfy(Self.isFoldingWhitespace) else { return nil }
    lexeme.phrase = Self.collapsed(phrase)
    lexeme.comments = Self.collapsed(comments.joined(separator: " "))
    return lexeme
  }

  private mutating func quotedString() -> String? {
    var text = ""
    while index < characters.count {
      let character = characters[index]
      index += 1
      switch character {
        case "\\":
          guard index < characters.count else { return nil }
          text.append(characters[index]); index += 1
        case "\"": return text
        default: text.append(character)
      }
    }
    return nil
  }

  private mutating func comment() -> String? {
    var text = "", depth = 1
    while index < characters.count {
      let character = characters[index]
      index += 1
      switch character {
        case "\\":
          guard index < characters.count else { return nil }
          text.append(characters[index]); index += 1
        case "(":
          depth += 1; text.append(character)
        case ")":
          depth -= 1
          if depth == 0 { return text }
          text.append(character)
        default: text.append(character)
      }
    }
    return nil
  }

  private mutating func angleAddress() -> String? {
    var text = ""
    while index < characters.count {
      let character = characters[index]
      index += 1
      switch character {
        case ">": return text
        case "<": return nil
        default: text.append(character)
      }
    }
    return nil
  }
}
