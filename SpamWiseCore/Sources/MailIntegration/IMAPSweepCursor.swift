struct IMAPSweepCursor: Codable, Sendable {
  var offset = 0
  var validity: UInt64?

  func currentOffset(validity: UInt64, count: Int) -> Int {
    self.validity == validity && offset >= 0 && offset < count ? offset : 0
  }
}
