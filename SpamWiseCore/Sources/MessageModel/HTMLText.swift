/**
 Single-pass lexical HTML-to-text conversion that never backtracks or loads resources.

 Comments and `script`, `style` and `title` content are dropped, tags become spaces or line
 breaks, and common entities are decoded. As in browsers, a comment also ends at `--!>`,
 only a quoted attribute value may contain `>`, and other `<!`, `<?` and `</` markup ends at
 its first `>`. Unterminated comments and skipped elements drop the rest of the input; once
 markup has no closing `>`, later `<` characters are kept as text.

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
  private static let skippedElements: Set<String> = ["script", "style", "title"]
  private static let lineBreakTags: Set<String> = ["br", "/p", "/div", "/li"]
  private static let namedEntities: [String: Unicode.Scalar] = [
    "lt": "<", "gt": ">", "quot": "\"", "amp": "&", "nbsp": " "
  ]

  private let input: [Unicode.Scalar]
  private let limit: Int
  private var index = 0
  private var output: [Unicode.Scalar] = []
  private var tagsCanClose = true
  private var unterminatedQuotes: Set<Unicode.Scalar> = []

  private init(_ html: String, limit: Int) {
    input = Array(html.unicodeScalars)
    self.limit = limit
  }

  /// Converts HTML into at most `limit` scalars of text, stopping once the limit is reached.
  static func text(from html: String, limit: Int) -> String {
    var scanner = Self(html, limit: limit)
    scanner.scan()
    return String(String.UnicodeScalarView(scanner.output))
  }

  private static func isASCIILetter(_ scalar: Unicode.Scalar) -> Bool {
    scalar.isASCII && scalar.properties.isAlphabetic
  }

  private static func endsTagName(_ scalar: Unicode.Scalar) -> Bool {
    scalar == ">" || scalar == "/" || attributeWhitespace.contains(scalar)
  }

  private static func decodedEntity(_ name: String) -> Unicode.Scalar? {
    guard name.hasPrefix("#") else { return namedEntities[name] }
    let number = name.dropFirst()
    let value =
      number.first == "x" || number.first == "X"
      ? UInt32(number.dropFirst(), radix: hexadecimalRadix) : UInt32(number)
    return value.flatMap(Unicode.Scalar.init)
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
      output.append("\n")
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
    output.append("<")
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
   its closing `>`.

   Follows the HTML tokenizer's tag states, so only a quoted value after an attribute name and
   `=` can contain `>`. An `=` in the tag name or at the start of an attribute name is an
   ordinary name character.
   */
  private mutating func tag(at nameStart: Int) -> (name: String, end: Int)? {
    let nameEnd = input[nameStart...].firstIndex(where: Self.endsTagName) ?? input.count
    let name = String(String.UnicodeScalarView(input[nameStart..<nameEnd].map(lowercased)))
    var position = nameEnd, state = TagState.beforeAttributeName
    while position < input.count {
      let scalar = input[position]
      if scalar == ">" { return (name, position + 1) }
      switch state {
        case .beforeAttributeName:
          if !Self.endsTagName(scalar) { state = .attributeName }
        case .attributeName, .afterAttributeName:
          if scalar == "=" {
            position = attributeValueEnd(from: position + 1)
            state = .beforeAttributeName
            continue
          }
          if scalar == "/" {
            state = .beforeAttributeName
          } else if Self.attributeWhitespace.contains(scalar) {
            state = .afterAttributeName
          } else if state == .afterAttributeName {
            state = .attributeName
          }
      }
      position += 1
    }
    return nil
  }

  /**
   Returns the position after an attribute value starting at or after `start`.

   An unquoted value ends before whitespace or `>`, and a missing value returns the position of
   its `>`. An unterminated quote begins an unquoted value; a quote found to be unterminated is
   never searched for again.
   */
  private mutating func attributeValueEnd(from start: Int) -> Int {
    let valueStart =
      input[start...].firstIndex { !Self.attributeWhitespace.contains($0) } ?? input.count
    guard valueStart < input.count else { return valueStart }
    let quote = input[valueStart]
    if Self.attributeQuotes.contains(quote), !unterminatedQuotes.contains(quote) {
      if let closing = input[(valueStart + 1)...].firstIndex(of: quote) { return closing + 1 }
      unterminatedQuotes.insert(quote)
    }
    return input[valueStart...].firstIndex { $0 == ">" || Self.attributeWhitespace.contains($0) }
      ?? input.count
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
    let start = index + 1
    let end = min(input.count, start + Self.maximumEntityScalars)
    if let semicolon = input[start..<end].firstIndex(of: ";"),
      let scalar = Self.decodedEntity(String(String.UnicodeScalarView(input[start..<semicolon])))
    {
      appendText(scalar)
      index = semicolon + 1
    } else {
      output.append("&"); index += 1
    }
  }

  private mutating func appendText(_ scalar: Unicode.Scalar) {
    if scalar == " " || scalar == "\t" { appendSpace() } else { output.append(scalar) }
  }

  private mutating func appendSpace() {
    if output.last != " " { output.append(" ") }
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

  /// Attribute positions of the HTML tokenizer that decide whether `=` begins a value.
  private enum TagState {
    case beforeAttributeName, attributeName, afterAttributeName
  }
}
