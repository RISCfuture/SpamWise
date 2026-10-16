extension Sequence where Element: Hashable {
  /// The elements in their original order, keeping only the first occurrence of each value.
  package func uniqued() -> [Element] {
    var seen = Set<Element>()
    return filter { seen.insert($0).inserted }
  }
}
