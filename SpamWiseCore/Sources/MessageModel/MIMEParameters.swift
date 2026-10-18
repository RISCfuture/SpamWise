import Foundation

/// One parameter of a ``MIMEHeaderValue``.
enum MIMEParameter: Equatable {
  /// The parameter is not present.
  case absent
  /// The parameter was given more than once, or its RFC 2231 sections were inconsistent.
  case ambiguous
  /// A plain value, still byte-preserved and possibly holding RFC 2047 encoded words.
  case raw(String)
  /// An RFC 2231 extended value, already decoded from its declared character set.
  case decoded(String)

  /// The value as written, without decoding; nil when absent or ambiguous.
  var value: String? {
    switch self {
      case .raw(let value), .decoded(let value): value
      case .absent, .ambiguous: nil
    }
  }

  /// The value as display text, decoding encoded words in a plain value.
  func text(issues: inout Set<DecodingIssue>) -> String? {
    switch self {
      case .raw(let value): MIMEParser.decodeWords(value, issues: &issues)
      case .decoded(let value): value
      case .absent, .ambiguous: nil
    }
  }
}

/**
 A Content-Type or Content-Disposition value: its lowercased token and its parameters.

 Parameter names are case-insensitive and values may be quoted strings with backslash escapes
 (RFC 2045). RFC 2231 extended (`name*=charset'language'value`) and continued (`name*0=`,
 `name*1*=`) forms are joined and decoded, with UTF-8 assumed when no charset is declared.
 Because mail clients can disagree about such values, a name given more than once or in more
 than one form, a section given twice, or sections that do not run contiguously from zero make
 that parameter ``MIMEParameter/ambiguous``.
 */
struct MIMEHeaderValue {
  /// The lowercased media type or disposition type, such as `text/plain` or `attachment`.
  let token: String
  private let parameters: [String: MIMEParameter]

  /// Parses a header value held in the parser's byte-preserving Latin-1 form.
  init(_ value: String, issues: inout Set<DecodingIssue>) {
    let segments = Self.segments(value)
    token = segments.first?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
    var forms: [String: ParameterForms] = [:]
    for segment in segments.dropFirst() {
      guard let (name, value) = Self.assignment(segment) else { continue }
      let (base, section) = Self.sectionedName(name)
      forms[base, default: ParameterForms()].add(value, section: section)
    }
    parameters = forms.mapValues { $0.resolved(issues: &issues) }
  }

  /// Splits at semicolons outside quoted strings.
  private static func segments(_ value: String) -> [String] {
    var segments: [String] = [], current = "", quoted = false, escaped = false
    for character in value {
      if escaped {
        escaped = false
      } else if quoted, character == "\\" {
        escaped = true
      } else if character == "\"" {
        quoted.toggle()
      } else if character == ";", !quoted {
        segments.append(current)
        current = ""
        continue
      }
      current.append(character)
    }
    return segments + [current]
  }

  /// Splits `name=value`, unquoting a quoted value and ending a bare value at whitespace.
  private static func assignment(_ segment: String) -> (name: String, value: String)? {
    guard let equals = segment.firstIndex(of: "=") else { return nil }
    let name = segment[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
    let value = segment[segment.index(after: equals)...].trimmingCharacters(in: .whitespaces)
    guard !name.isEmpty else { return nil }
    guard value.first == "\"" else {
      return (name, String(value.prefix { !$0.isWhitespace }))
    }
    var unquoted = "", escaped = false
    for character in value.dropFirst() {
      if escaped {
        unquoted.append(character)
        escaped = false
      } else if character == "\\" {
        escaped = true
      } else if character == "\"" {
        break
      } else {
        unquoted.append(character)
      }
    }
    return (name, unquoted)
  }

  /// Separates an RFC 2231 name such as `filename*1*` into its base name and section.
  private static func sectionedName(_ name: String) -> (String, Section) {
    guard let star = name.firstIndex(of: "*") else { return (name, .plain) }
    let base = String(name[..<star])
    var suffix = name[name.index(after: star)...]
    guard !suffix.isEmpty else { return (base, .extended) }
    let extended = suffix.last == "*"
    if extended { suffix = suffix.dropLast() }
    guard let number = Int(suffix), number >= 0, String(number) == suffix else {
      return (name, .plain)
    }
    return (base, .continued(number, extended: extended))
  }

  /// Returns the named parameter, matched case-insensitively.
  func parameter(_ name: String) -> MIMEParameter { parameters[name.lowercased()] ?? .absent }

  /// The syntactic form in which a parameter value was given.
  private enum Section {
    case plain, extended
    case continued(Int, extended: Bool)
  }

  /// Every value given for one parameter name, grouped by form.
  private struct ParameterForms {
    private static let percentSign = UInt8(ascii: "%")
    private static let percentEscapeLength = 3
    /// An extended value is `charset'language'text`.
    private static let extendedValueFields = 3
    private var plain: [String] = []
    private var extended: [String] = []
    private var sections: [Int: [(value: String, extended: Bool)]] = [:]

    /// Joins RFC 2231 sections, percent-decoding extended ones in the first section's charset.
    private static func decoded(
      _ sections: [(value: String, extended: Bool)],
      issues: inout Set<DecodingIssue>
    ) -> String {
      var charset = "utf-8", bytes: [UInt8] = []
      for (index, section) in sections.enumerated() {
        var value = Substring(section.value)
        if index == 0, section.extended {
          let fields = value.split(
            separator: "'",
            maxSplits: extendedValueFields - 1,
            omittingEmptySubsequences: false
          )
          if fields.count == extendedValueFields {
            if !fields[0].isEmpty { charset = String(fields[0]) }
            value = fields[2]
          } else {
            issues.insert(.invalidEncodedWord)
          }
        }
        let raw = MIMEParser.latin1Bytes(value)
        bytes += section.extended ? percentDecoded(raw, issues: &issues) : raw
      }
      return MIMEParser.decode(Data(bytes), charset: charset, issues: &issues)
    }

    /// Decodes `%XX` escapes, keeping an invalid escape literally.
    private static func percentDecoded(_ bytes: [UInt8], issues: inout Set<DecodingIssue>)
      -> [UInt8]
    {
      var result: [UInt8] = [], index = 0
      while index < bytes.count {
        if bytes[index] == percentSign, index + percentEscapeLength <= bytes.count,
          let high = MIMEParser.hexValue(bytes[index + 1]),
          let low = MIMEParser.hexValue(bytes[index + 2])
        {
          result.append(high << 4 | low)
          index += percentEscapeLength
        } else {
          if bytes[index] == percentSign { issues.insert(.invalidEncodedWord) }
          result.append(bytes[index])
          index += 1
        }
      }
      return result
    }

    mutating func add(_ value: String, section: Section) {
      switch section {
        case .plain: plain.append(value)
        case .extended: extended.append(value)
        case .continued(let number, let isExtended):
          sections[number, default: []].append((value, isExtended))
      }
    }

    func resolved(issues: inout Set<DecodingIssue>) -> MIMEParameter {
      let forms = [!plain.isEmpty, !extended.isEmpty, !sections.isEmpty].filter { $0 }.count
      guard forms <= 1, plain.count <= 1, extended.count <= 1,
        sections.values.allSatisfy({ $0.count == 1 }),
        sections.isEmpty || sections.keys.sorted() == Array(0..<sections.count)
      else { return .ambiguous }
      if let value = extended.first {
        return .decoded(Self.decoded([(value, true)], issues: &issues))
      }
      if !sections.isEmpty {
        let ordered = sections.keys.sorted().compactMap { sections[$0]?.first }
        guard ordered.contains(where: \.extended) else {
          return .raw(ordered.map(\.value).joined())
        }
        return .decoded(Self.decoded(ordered, issues: &issues))
      }
      return plain.first.map(MIMEParameter.raw) ?? .absent
    }
  }
}
