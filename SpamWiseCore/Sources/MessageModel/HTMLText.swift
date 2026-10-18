/**
 Single-pass lexical HTML-to-text conversion that never backtracks or loads resources.

 Comments and `script`, `style` and `title` content are dropped, tags become spaces or line
 breaks, and common entities are decoded, including numeric references that lack their closing
 semicolon. As in browsers, a comment also ends at `--!>`, only a quoted attribute value may
 contain `>`, and other `<!`, `<?` and `</` markup ends at its first `>`. Unterminated comments
 and skipped elements drop the rest of the input; once markup has no closing `>`, later `<`
 characters are kept as text.

 Alongside the text, the conversion keeps a link source: the same text with the normalized
 values of URL-bearing attributes inserted where their tags appear, so URLs can be found in
 first-appearance order without reading comments or skipped element content.

 Every search resumes where the previous one stopped, so conversion is linear in the input,
 which the parser bounds at 2 MB; it therefore needs no step budget or cancellation check.
 */
struct HTMLText {
  private static let commentOpening = Array("<!--".unicodeScalars)
  private static let commentDashes = Array("--".unicodeScalars)
  private static let commentClosings = [Array(">".unicodeScalars), Array("!>".unicodeScalars)]
  private static let abruptCommentClosings = [
    Array(">".unicodeScalars), Array("->".unicodeScalars)
  ]
  private static let attributeQuotes: Set<Unicode.Scalar> = ["\"", "'"]
  private static let attributeWhitespace: Set<Unicode.Scalar> = [" ", "\t", "\n", "\r", "\u{0C}"]
  private static let asciiCaseOffset = Unicode.Scalar("a").value - Unicode.Scalar("A").value
  private static let maximumEntityScalars = 10
  private static let hexadecimalRadix = 16
  private static let decimalRadix = 10
  private static let skippedElements: Set<String> = ["script", "style", "title"]
  private static let lineBreakTags: Set<String> = ["br", "/p", "/div", "/li"]
  private static let namedEntities: [String: Unicode.Scalar] = [
    "lt": "<", "gt": ">", "quot": "\"", "amp": "&", "nbsp": " ", "apos": "'", "colon": ":",
    "sol": "/", "bsol": "\\", "period": ".", "quest": "?", "equals": "=", "num": "#",
    "percnt": "%", "commat": "@", "lowbar": "_", "hyphen": "-"
  ]
  private static let urlAttributes: Set<String> = [
    "href", "src", "srcset", "action", "formaction", "background", "poster", "cite", "data",
    "content"
  ]
  private static let removedURLScalars: Set<Unicode.Scalar> = ["\t", "\n", "\r"]
  private static let urlSlashes: Set<Unicode.Scalar> = ["/", "\\"]
  private static let schemeRelativePrefixLength = 2
  private static let defaultScheme = Array("https:".unicodeScalars)
  private static let maximumTrimmedScalar: Unicode.Scalar = " "

  private let input: [Unicode.Scalar]
  private let limit: Int
  private var index = 0
  private var output: [Unicode.Scalar] = []
  private var linkSource: [Unicode.Scalar] = []
  private var tagsCanClose = true
  private var unterminatedQuotes: Set<Unicode.Scalar> = []

  private init(_ html: String, limit: Int) {
    input = Array(html.unicodeScalars)
    self.limit = limit
  }

  /// Converts HTML into at most `limit` scalars of text, stopping once the limit is reached.
  static func convert(_ html: String, limit: Int) -> Conversion {
    var scanner = Self(html, limit: limit)
    scanner.scan()
    return Conversion(
      text: String(String.UnicodeScalarView(scanner.output)),
      linkSource: String(String.UnicodeScalarView(scanner.linkSource))
    )
  }

  private static func isASCIILetter(_ scalar: Unicode.Scalar) -> Bool {
    scalar.isASCII && scalar.properties.isAlphabetic
  }

  private static func endsTagName(_ scalar: Unicode.Scalar) -> Bool {
    scalar == ">" || scalar == "/" || attributeWhitespace.contains(scalar)
  }

  /**
   Decodes the character reference whose `&` is at `start`, returning its scalar and the
   position after it.

   A named reference needs its closing semicolon; a numeric one may omit it, as in browsers.
   */
  private static func entity(in scalars: [Unicode.Scalar], at start: Int, end: Int)
    -> (scalar: Unicode.Scalar, end: Int)?
  {
    let nameStart = start + 1, searchEnd = min(end, start + 1 + maximumEntityScalars)
    guard nameStart < searchEnd else { return nil }
    guard scalars[nameStart] == "#" else {
      guard let semicolon = scalars[nameStart..<searchEnd].firstIndex(of: ";") else { return nil }
      return namedEntities[string(scalars[nameStart..<semicolon])].map { ($0, semicolon + 1) }
    }
    let hexadecimal =
      nameStart + 1 < searchEnd && (scalars[nameStart + 1] == "x" || scalars[nameStart + 1] == "X")
    let digitsStart = min(searchEnd, nameStart + (hexadecimal ? 2 : 1))
    let radix = hexadecimal ? hexadecimalRadix : decimalRadix
    let digitsEnd =
      scalars[digitsStart..<searchEnd].firstIndex { !isDigit($0, radix: radix) } ?? searchEnd
    guard digitsStart < digitsEnd,
      let value = UInt32(string(scalars[digitsStart..<digitsEnd]), radix: radix),
      let scalar = Unicode.Scalar(value)
    else { return nil }
    return (scalar, digitsEnd < end && scalars[digitsEnd] == ";" ? digitsEnd + 1 : digitsEnd)
  }

  private static func isDigit(_ scalar: Unicode.Scalar, radix: Int) -> Bool {
    scalar.isASCII && Character(scalar).hexDigitValue.map { $0 < radix } == true
  }

  /**
   Reads an attribute value the way browsers read a URL: entities decoded, tabs and line breaks
   removed, surrounding spaces and controls trimmed, and a scheme-relative `//host` or `\\host`
   given an `https:` scheme.
   */
  private static func urlValue(_ scalars: [Unicode.Scalar], in range: Range<Int>)
    -> [Unicode.Scalar]
  {
    var value: [Unicode.Scalar] = [], position = range.lowerBound
    while position < range.upperBound {
      if scalars[position] == "&",
        let entity = entity(in: scalars, at: position, end: range.upperBound)
      {
        value.append(entity.scalar)
        position = entity.end
      } else {
        if !removedURLScalars.contains(scalars[position]) { value.append(scalars[position]) }
        position += 1
      }
    }
    let trimmed = value.drop { $0 <= maximumTrimmedScalar }.reversed()
      .drop { $0 <= maximumTrimmedScalar }.reversed()
    let isSchemeRelative =
      trimmed.count > schemeRelativePrefixLength
      && trimmed.prefix(schemeRelativePrefixLength).allSatisfy(urlSlashes.contains)
    return (isSchemeRelative ? defaultScheme : []) + trimmed
  }

  private static func string(_ scalars: some Sequence<Unicode.Scalar>) -> String {
    String(String.UnicodeScalarView(scalars))
  }

  private mutating func scan() {
    while index < input.count, output.count < limit {
      let scalar = input[index]
      if scalar == "<", tagsCanClose, startsMarkup(at: index + 1) {
        skipMarkup()
      } else if scalar == "&" {
        appendEntity()
      } else {
        appendText(scalar)
        index += 1
      }
    }
  }

  private func startsMarkup(at position: Int) -> Bool {
    guard position < input.count else { return false }
    let scalar = input[position]
    return Self.isASCIILetter(scalar) || "/!?".unicodeScalars.contains(scalar)
  }

  private mutating func skipMarkup() {
    if matches(Self.commentOpening, at: index) {
      skipComment()
      return
    }
    let closing = input[index + 1] == "/"
    let nameStart = index + (closing ? 2 : 1)
    guard nameStart < input.count, Self.isASCIILetter(input[nameStart]) else {
      skipBogusComment()
      return
    }
    guard let tag = tag(at: nameStart) else {
      keepUnterminatedMarkup()
      return
    }
    index = tag.end
    if !closing, Self.skippedElements.contains(tag.name) {
      skipElementContent(tag.name)
    } else if Self.lineBreakTags.contains((closing ? "/" : "") + tag.name) {
      emit("\n")
    } else {
      appendSpace()
    }
  }

  /// Skips `<!`, `<?` or `</` markup that is not a comment or tag up to its first `>`.
  private mutating func skipBogusComment() {
    guard let end = input[(index + 1)...].firstIndex(of: ">") else {
      keepUnterminatedMarkup()
      return
    }
    index = end + 1
  }

  /// Keeps an unclosed `<` as text; no later markup can close either, so all later `<` are text.
  private mutating func keepUnterminatedMarkup() {
    tagsCanClose = false
    emit("<")
    index += 1
  }

  /// Skips a comment, including the empty `<!-->` and `<!--->` forms that close immediately.
  private mutating func skipComment() {
    let contentStart = index + Self.commentOpening.count
    if let abrupt = Self.abruptCommentClosings.first(where: { matches($0, at: contentStart) }) {
      index = contentStart + abrupt.count
    } else {
      index = commentEnd(from: contentStart) ?? input.count
    }
  }

  /// Returns the position after the first `-->` or `--!>`.
  private func commentEnd(from start: Int) -> Int? {
    var search = start
    while let dashesEnd = position(after: Self.commentDashes, from: search) {
      if let closing = Self.commentClosings.first(where: { matches($0, at: dashesEnd) }) {
        return dashesEnd + closing.count
      }
      search = dashesEnd - 1
    }
    return nil
  }

  /**
   Reads a start or end tag from its name, returning the lowercased name and the position after
   its closing `>`, and adds its URL-bearing attribute values to the link source.

   Follows the HTML tokenizer's tag states, so only a quoted value after an attribute name and
   `=` can contain `>`. An `=` in the tag name or at the start of an attribute name is an
   ordinary name character.
   */
  private mutating func tag(at nameStart: Int) -> (name: String, end: Int)? {
    let nameEnd = input[nameStart...].firstIndex(where: Self.endsTagName) ?? input.count
    let name = Self.string(input[nameStart..<nameEnd].map(lowercased))
    var position = nameEnd, state = TagState.beforeAttributeName
    var attributeName = position..<position
    while position < input.count {
      let scalar = input[position]
      if scalar == ">" { return (name, position + 1) }
      switch state {
        case .beforeAttributeName:
          if !Self.endsTagName(scalar) {
            state = .attributeName
            attributeName = position..<(position + 1)
          }
        case .attributeName, .afterAttributeName:
          if scalar == "=" {
            let value = attributeValue(from: position + 1)
            recordLink(named: attributeName, value: value.range)
            position = value.end
            state = .beforeAttributeName
            continue
          }
          if scalar == "/" {
            state = .beforeAttributeName
          } else if Self.attributeWhitespace.contains(scalar) {
            state = .afterAttributeName
          } else if state == .afterAttributeName {
            state = .attributeName
            attributeName = position..<(position + 1)
          } else {
            attributeName = attributeName.lowerBound..<(position + 1)
          }
      }
      position += 1
    }
    return nil
  }

  /**
   Returns the range of an attribute value starting at or after `start`, without its quotes,
   and the position after it.

   An unquoted value ends before whitespace or `>`, and a missing value is empty and ends at
   its `>`. An unterminated quote begins an unquoted value; a quote found to be unterminated is
   never searched for again.
   */
  private mutating func attributeValue(from start: Int) -> (range: Range<Int>, end: Int) {
    let valueStart =
      input[start...].firstIndex { !Self.attributeWhitespace.contains($0) } ?? input.count
    guard valueStart < input.count else { return (valueStart..<valueStart, valueStart) }
    let quote = input[valueStart]
    if Self.attributeQuotes.contains(quote), !unterminatedQuotes.contains(quote) {
      if let closing = input[(valueStart + 1)...].firstIndex(of: quote) {
        return ((valueStart + 1)..<closing, closing + 1)
      }
      unterminatedQuotes.insert(quote)
    }
    let end =
      input[valueStart...].firstIndex { $0 == ">" || Self.attributeWhitespace.contains($0) }
      ?? input.count
    return (valueStart..<end, end)
  }

  /// Adds a URL-bearing attribute's value to the link source, separated by spaces.
  private mutating func recordLink(named name: Range<Int>, value: Range<Int>) {
    guard Self.urlAttributes.contains(Self.string(input[name].map(lowercased))) else { return }
    linkSource.append(" ")
    linkSource += Self.urlValue(input, in: value)
    linkSource.append(" ")
  }

  /// Skips raw text up to and including the element's end tag, which must be followed by
  /// whitespace, `/` or `>`.
  private mutating func skipElementContent(_ name: String) {
    let closingPattern = Array(("</" + name).unicodeScalars)
    var search = index
    while let close = position(after: closingPattern, from: search) {
      if close < input.count, !Self.endsTagName(input[close]) {
        search = close
        continue
      }
      index = tag(at: close - name.unicodeScalars.count)?.end ?? input.count
      return
    }
    index = input.count
  }

  private mutating func appendEntity() {
    if let entity = Self.entity(in: input, at: index, end: input.count) {
      appendText(entity.scalar)
      index = entity.end
    } else {
      emit("&")
      index += 1
    }
  }

  private mutating func appendText(_ scalar: Unicode.Scalar) {
    if scalar == " " || scalar == "\t" { appendSpace() } else { emit(scalar) }
  }

  private mutating func appendSpace() {
    if output.last != " " { emit(" ") }
  }

  /// Appends a text scalar to both the text and the link source.
  private mutating func emit(_ scalar: Unicode.Scalar) {
    output.append(scalar)
    linkSource.append(scalar)
  }

  /// Case-insensitively finds an ASCII pattern and returns the position just after it.
  private func position(after pattern: [Unicode.Scalar], from start: Int) -> Int? {
    guard let first = pattern.first, start < input.count else { return nil }
    var candidate = start
    while candidate + pattern.count <= input.count {
      if lowercased(input[candidate]) == first, matches(pattern, at: candidate) {
        return candidate + pattern.count
      }
      candidate += 1
    }
    return nil
  }

  private func matches(_ pattern: [Unicode.Scalar], at position: Int) -> Bool {
    guard position + pattern.count <= input.count else { return false }
    return pattern.indices.allSatisfy { lowercased(input[position + $0]) == pattern[$0] }
  }

  private func lowercased(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
    ("A"..."Z").contains(scalar)
      ? Unicode.Scalar(scalar.value + Self.asciiCaseOffset) ?? scalar : scalar
  }

  /// Converted text and the link source that also holds URL-bearing attribute values.
  struct Conversion {
    /// The visible text.
    var text: String
    /// The visible text with URL-bearing attribute values inserted in document order.
    var linkSource: String
  }

  /// Attribute positions of the HTML tokenizer that decide whether `=` begins a value.
  private enum TagState {
    case beforeAttributeName, attributeName, afterAttributeName
  }
}
