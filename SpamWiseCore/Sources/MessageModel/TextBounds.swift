extension StringProtocol {
  /**
   The leading text, up to `maximum` Unicode scalars.

   A character count lets one character carry any number of combining marks, so text bounded for
   a prompt or a record is bounded by scalars.
   */
  public func prefix(unicodeScalars maximum: Int) -> String {
    String(String.UnicodeScalarView(unicodeScalars.prefix(maximum)))
  }
}
