/**
 Single-pass lexical HTML-to-text conversion that never backtracks or loads resources.

 Comments and `script`, `style` and `title` content are dropped, tags become spaces or line
 breaks, and common entities are decoded, including numeric references that lack their closing
 semicolon. As in browsers, a comment also ends at `--!>`, only a quoted attribute value may
 contain `>`, and other `<!`, `<?` and `</` markup ends at its first `>`. Unterminated comments
 and skipped elements drop the rest of the input; once markup has no closing `>`, later `<`
 characters are kept as text.

 Text inside concealed elements is kept apart from the visible text: elements with a `hidden`
 attribute, zero `width` or `height` attributes, or inline styles that hide them, make them
 zero-size or make them transparent. Open elements are tracked by name, so an end tag closes
 the latest open element it names and any opened inside it; void elements never open. Browsers
 build a fuller tree, so concealment is a heuristic: it orders text and links, and never drops
 them.

 Alongside the text, the conversion keeps link sources ranked by ``LinkVisibility``: visible
 text and anchor `href`s, then other URL-bearing attributes, then concealed or `aria-hidden`
 text and attributes. Each holds normalized URL values where their tags appear, so URLs can be
 found in first-appearance order within a rank without reading comments or skipped element
 content.

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
  private static let voidElements: Set<String> = [
    "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track",
    "wbr"
  ]
  private static let anchorElements: Set<String> = ["a", "area"]
  /// Attributes that conceal content or hide it from assistive technology: `aria-hidden`, inline
  /// style, `hidden`, and a zero `width` or `height`.
  private static let visibilityAttributes: Set<String> = [
    "aria-hidden", "style", "hidden", "width", "height"
  ]
  private static let maximumOpenElements = 256
  private static let zeroSizeProperties: Set<String> = [
    "font-size", "width", "height", "max-width", "max-height", "opacity"
  ]
  private static let hidingDeclarations: Set<String> = [
    "display:none", "visibility:hidden", "visibility:collapse", "color:transparent"
  ]
  private static let numberScalars = Set("0123456789.+-".unicodeScalars)
  private static let importantMarker = "!important"
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
  private var concealedOutput: [Unicode.Scalar] = []
  private var visibleLinkSource: [Unicode.Scalar] = []
  private var attributeLinkSource: [Unicode.Scalar] = []
  private var hiddenLinkSource: [Unicode.Scalar] = []
  private var openElements: [OpenElement] = []
  private var concealingElements = 0
  private var ariaHiddenElements = 0
  private var isConcealed: Bool { concealingElements > 0 }
  private var linksAreHidden: Bool { isConcealed || ariaHiddenElements > 0 }
  private var tagsCanClose = true
  private var unterminatedQuotes: Set<Unicode.Scalar> = []

  private init(_ html: String, limit: Int) {
    input = Array(html.unicodeScalars)
    self.limit = limit
  }

  /// Converts HTML into at most `limit` scalars each of visible and concealed text, stopping
  /// once the visible text reaches the limit.
  static func convert(_ html: String, limit: Int) -> Conversion {
    var scanner = Self(html, limit: limit)
    scanner.scan()
    return Conversion(
      text: string(scanner.output),
      concealedText: string(scanner.concealedOutput),
      linkSources: [
        .visible: string(scanner.visibleLinkSource),
        .attribute: string(scanner.attributeLinkSource),
        .hidden: string(scanner.hiddenLinkSource)
      ]
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
    let value = decodedValue(scalars, in: range).filter { !removedURLScalars.contains($0) }
    let trimmed = value.drop { $0 <= maximumTrimmedScalar }.reversed()
      .drop { $0 <= maximumTrimmedScalar }.reversed()
    let isSchemeRelative =
      trimmed.count > schemeRelativePrefixLength
      && trimmed.prefix(schemeRelativePrefixLength).allSatisfy(urlSlashes.contains)
    return (isSchemeRelative ? defaultScheme : []) + trimmed
  }

  /// An attribute value with its character references decoded.
  private static func decodedValue(_ scalars: [Unicode.Scalar], in range: Range<Int>)
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
        value.append(scalars[position])
        position += 1
      }
    }
    return value
  }

  private static func string(_ scalars: some Sequence<Unicode.Scalar>) -> String {
    String(String.UnicodeScalarView(scalars))
  }

  /// Whether an inline style hides its element, makes it zero-size or makes it transparent.
  private static func hidesContent(style: String) -> Bool {
    compacted(style).split(separator: ";").contains { declaration in
      let text =
        declaration.hasSuffix(importantMarker)
        ? declaration.dropLast(importantMarker.count) : declaration[...]
      guard let colon = text.firstIndex(of: ":") else { return false }
      let property = String(text[..<colon]), value = text[text.index(after: colon)...]
      return hidingDeclarations.contains(String(text))
        || (zeroSizeProperties.contains(property) && isZero(value))
    }
  }

  /// Lowercased text without whitespace, as CSS and enumerated attribute values compare.
  private static func compacted(_ value: String) -> String {
    string(value.lowercased().unicodeScalars.filter { !$0.properties.isWhitespace })
  }

  /// Whether a CSS or attribute length is zero in any unit.
  private static func isZero(_ value: some StringProtocol) -> Bool {
    let number = value.unicodeScalars.prefix { numberScalars.contains($0) }
    return number.contains { ("0"..."9").contains($0) } && Double(string(number)) == 0
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
    if closing {
      close(tag.name)
    } else {
      open(tag)
    }
    if !closing, Self.skippedElements.contains(tag.name) {
      skipElementContent(tag.name)
    } else if Self.lineBreakTags.contains((closing ? "/" : "") + tag.name) {
      emit("\n")
    } else {
      appendSpace()
    }
  }

  /// Records a start tag's links, then tracks it as open unless it is void or skipped.
  private mutating func open(_ tag: Tag) {
    var element = OpenElement(name: tag.name, conceals: false, ariaHidden: false)
    var links: [(name: String, value: Range<Int>)] = []
    for attribute in tag.attributes {
      let name = Self.string(input[attribute.name].map(lowercased))
      if Self.urlAttributes.contains(name) { links.append((name, attribute.value)) }
      guard Self.visibilityAttributes.contains(name) else { continue }
      let value = Self.string(Self.decodedValue(input, in: attribute.value))
      switch name {
        case "aria-hidden":
          element.ariaHidden = element.ariaHidden || Self.compacted(value) == "true"
        case "style": element.conceals = element.conceals || Self.hidesContent(style: value)
        case "hidden": element.conceals = true
        default: element.conceals = element.conceals || Self.isZero(value)
      }
    }
    for link in links {
      let visibility: LinkVisibility =
        if linksAreHidden || element.conceals || element.ariaHidden {
          .hidden
        } else if Self.anchorElements.contains(tag.name) && link.name == "href" {
          .visible
        } else {
          .attribute
        }
      appendLink([" "] + Self.urlValue(input, in: link.value) + [" "], to: visibility)
    }
    guard !Self.voidElements.contains(tag.name), !Self.skippedElements.contains(tag.name) else {
      return
    }
    push(element)
  }

  /// Tracks an open element; at the nesting limit it replaces the innermost one, keeping each
  /// way either of them hides content.
  private mutating func push(_ element: OpenElement) {
    var element = element
    if openElements.count >= Self.maximumOpenElements {
      let innermost = openElements.removeLast()
      count(innermost, by: -1)
      element.conceals = element.conceals || innermost.conceals
      element.ariaHidden = element.ariaHidden || innermost.ariaHidden
    }
    openElements.append(element)
    count(element, by: 1)
  }

  /// Closes the latest open element named `name` and every element opened inside it.
  private mutating func close(_ name: String) {
    guard let position = openElements.lastIndex(where: { $0.name == name }) else { return }
    for element in openElements[position...] { count(element, by: -1) }
    openElements.removeSubrange(position...)
  }

  private mutating func count(_ element: OpenElement, by change: Int) {
    if element.conceals { concealingElements += change }
    if element.ariaHidden { ariaHiddenElements += change }
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
   Reads a start or end tag from its name, returning its lowercased name, the position after its
   closing `>` and its attributes.

   Follows the HTML tokenizer's tag states, so only a quoted value after an attribute name and
   `=` can contain `>`. An `=` in the tag name or at the start of an attribute name is an
   ordinary name character, and an attribute without `=` has an empty value.
   */
  private mutating func tag(at nameStart: Int) -> Tag? {
    let nameEnd = input[nameStart...].firstIndex(where: Self.endsTagName) ?? input.count
    let name = Self.string(input[nameStart..<nameEnd].map(lowercased))
    var position = nameEnd, state = TagState.beforeAttributeName
    var attributes: [Tag.Attribute] = [], valueless: Range<Int>?
    while position < input.count {
      let scalar = input[position]
      if scalar == ">" {
        if let valueless { attributes.append(.init(valueless: valueless)) }
        return Tag(name: name, end: position + 1, attributes: attributes)
      }
      switch state {
        case .beforeAttributeName:
          if !Self.endsTagName(scalar) {
            if let valueless { attributes.append(.init(valueless: valueless)) }
            state = .attributeName
            valueless = position..<(position + 1)
          }
        case .attributeName, .afterAttributeName:
          if scalar == "=", let attributeName = valueless {
            let value = attributeValue(from: position + 1)
            attributes.append(.init(name: attributeName, value: value.range))
            valueless = nil
            position = value.end
            state = .beforeAttributeName
            continue
          }
          if scalar == "/" {
            state = .beforeAttributeName
          } else if Self.attributeWhitespace.contains(scalar) {
            state = .afterAttributeName
          } else if state == .afterAttributeName {
            if let valueless { attributes.append(.init(valueless: valueless)) }
            state = .attributeName
            valueless = position..<(position + 1)
          } else if let attributeName = valueless {
            valueless = attributeName.lowerBound..<(position + 1)
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
    if (isConcealed ? concealedOutput.last : output.last) != " " { emit(" ") }
  }

  /// Appends a text scalar to the visible or concealed text and to its ranked link source.
  private mutating func emit(_ scalar: Unicode.Scalar) {
    if !isConcealed {
      output.append(scalar)
    } else if concealedOutput.count < limit {
      concealedOutput.append(scalar)
    }
    appendLink(CollectionOfOne(scalar), to: linksAreHidden ? .hidden : .visible)
  }

  private mutating func appendLink(
    _ scalars: some Collection<Unicode.Scalar>,
    to visibility: LinkVisibility
  ) {
    switch visibility {
      case .visible: visibleLinkSource += scalars
      case .attribute: attributeLinkSource += scalars
      case .hidden: hiddenLinkSource += scalars
    }
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

  /// Converted text and the link sources that also hold URL-bearing attribute values.
  struct Conversion {
    /// The visible text.
    var text: String
    /// Text inside concealed elements.
    var concealedText: String
    /// Text and URL-bearing attribute values in document order, by how visible they are.
    var linkSources: [LinkVisibility: String]
  }

  /// A start or end tag and the attributes it was written with.
  private struct Tag {
    var name: String
    /// The position after the tag's closing `>`.
    var end: Int
    var attributes: [Attribute]

    /// The input ranges of one attribute's name and its value without quotes.
    struct Attribute {
      var name: Range<Int>
      var value: Range<Int>

      init(name: Range<Int>, value: Range<Int>) {
        self.name = name; self.value = value
      }

      /// An attribute written without `=`, whose value is empty.
      init(valueless name: Range<Int>) {
        self.init(name: name, value: name.upperBound..<name.upperBound)
      }
    }
  }

  /// An element whose end tag has not been read, and how it hides its content.
  private struct OpenElement {
    var name: String
    /// Whether attributes or inline style conceal the element's content from view.
    var conceals: Bool
    /// Whether the element is hidden from assistive technology, though still shown.
    var ariaHidden: Bool
  }

  /// Attribute positions of the HTML tokenizer that decide whether `=` begins a value.
  private enum TagState {
    case beforeAttributeName, attributeName, afterAttributeName
  }
}

/// How prominently a message shows a link, most prominent first.
enum LinkVisibility: CaseIterable {
  /// Visible text, including anchor text, and the `href` of a visible anchor.
  case visible
  /// Any other URL-bearing attribute of a visible element, such as an image source.
  case attribute
  /// Text and attributes inside concealed or `aria-hidden` elements.
  case hidden
}
