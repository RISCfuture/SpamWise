import Foundation
import Testing
import SpamWiseCore
@testable import SpamWiseCommon

@Suite
struct `Account health summaries` {
  private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

  @Test
  func `report an account no check has reached as not checked`() {
    #expect(AccountHealthSummary(health: nil, now: now).state == .notChecked)
    #expect(
      AccountHealthSummary(health: MailScanHealth(accountName: "A"), now: now).state
        == .notChecked
    )
  }

  @Test
  func `report the latest successful read while checks run on schedule`() {
    let health = checked(minutesAgo: 2)
    let summary = AccountHealthSummary(health: health, now: now)
    #expect(summary.state == .checked(minutesAgo(2)))
    #expect(summary.coverage == health.coverage)
  }

  @Test
  func `report a late check once none has started for fifteen minutes`() {
    #expect(
      AccountHealthSummary(health: checked(minutesAgo: 14), now: now).state
        == .checked(minutesAgo(14))
    )
    #expect(
      AccountHealthSummary(health: checked(minutesAgo: 16), now: now).state
        == .late(lastChecked: minutesAgo(16))
    )
  }

  @Test
  func `put a failure ahead of lateness and a stall ahead of both`() {
    var health = checked(minutesAgo: 30)
    health.recordFailure("Mail didn’t respond.")
    #expect(
      AccountHealthSummary(health: health, now: now).state == .failing("Mail didn’t respond.")
    )
    health.consecutiveTimeouts = MailScanHealth.shrinkingTimeouts
    #expect(AccountHealthSummary(health: health, now: now).state == .stalled)
  }

  private func minutesAgo(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }

  private func checked(minutesAgo minutes: Double) -> MailScanHealth {
    var health = MailScanHealth(accountName: "Account")
    health.lastAttempt = minutesAgo(minutes)
    health.lastSuccess = minutesAgo(minutes)
    health.coverage.classified = 5
    health.coverage.reviewed = 1
    return health
  }
}

@Suite
struct `Trusted server lists` {
  @Test
  func `split entered servers on commas, spaces and new lines`() {
    #expect(
      AuthenticationTrustModel.servers(in: "mx.google.com, mx.icloud.example\n  relay.example ,")
        == ["mx.google.com", "mx.icloud.example", "relay.example"]
    )
    #expect(AuthenticationTrustModel.servers(in: "  \n").isEmpty)
  }
}
