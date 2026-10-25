extension Character {
  /// Treats only ASCII whitespace as folding, since raw 8-bit header bytes appear as Latin-1.
  var isFoldingWhitespace: Bool { isASCII && isWhitespace }
}

extension StringProtocol {
  /// The text without leading or trailing folding whitespace.
  var trimmingFoldingWhitespace: String {
    guard let first = firstIndex(where: { !$0.isFoldingWhitespace }),
      let last = lastIndex(where: { !$0.isFoldingWhitespace })
    else { return "" }
    return String(self[first...last])
  }
}
