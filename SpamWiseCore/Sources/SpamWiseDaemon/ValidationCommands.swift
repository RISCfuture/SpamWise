import ArgumentParser
import Foundation
import MailIntegration
import SpamWiseCore

/// Checks the account read-only and records or revokes daemon validation.
struct ValidateCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "validate",
    abstract: "Check the account read-only and record daemon validation.",
    discussion: """
      Authenticates, discovers mailbox roles and examines Inbox without changing mail. When the \
      server supports MOVE and has a unique Junk mailbox, records validation for this exact \
      endpoint and adds the account to the store's validated accounts; otherwise revokes the \
      daemon's validation, which turns dry run back on when no validated account remains. The \
      app's incoming route and transport are never changed.
      """
  )

  @OptionGroup var options: ConfigurationOptions

  func run() async throws {
    let options = options
    try await runCancellable {
      let context = try options.load()
      let account = context.configuration.account
      let check = try await context.adapter(allowingActions: false).validateReadOnly()
      try await context.reportingSettingChanges {
        let validated = try await IMAPAccountValidation.record(
          check,
          for: account,
          scope: .daemon,
          store: context.store
        )
        print(
          validated
            ? String(
              localized: "Read-only check passed; Inbox and Junk validated for this endpoint.",
              bundle: .module
            )
            : String(
              localized:
                "Read-only check passed, but the server lacks MOVE or a unique Junk mailbox; validation revoked.",
              bundle: .module
            )
        )
      }
    }
  }
}

/// Moves one disposable probe message to Junk and back, then records daemon validation.
struct ProbeCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "probe",
    abstract: "Move a disposable probe message to Junk and back.",
    discussion: """
      Only an Inbox message whose subject starts with [SpamWise Probe] is eligible. After both \
      moves are verified, records validation for this exact endpoint and adds the account to the \
      store's validated accounts. The app's incoming route, transport and dry-run setting are \
      never changed.
      """
  )

  @OptionGroup var options: ConfigurationOptions

  @Argument(help: "UID of the probe message in Inbox.")
  var uid: UInt32

  func validate() throws {
    guard uid > 0 else { throw DaemonUsageError.invalidProbeUID }
  }

  func run() async throws {
    let options = options, uid = uid
    try await runCancellable {
      let context = try options.load()
      let account = context.configuration.account
      _ = try await context.adapter(allowingActions: false).testDisposableMessage(uid: uid)
      print(String(localized: "Disposable probe restored to Inbox.", bundle: .module))
      try await context.reportingSettingChanges {
        try await IMAPAccountValidation.record(account, scope: .daemon, store: context.store)
        print(String(localized: "Daemon validation recorded for this endpoint.", bundle: .module))
      }
    }
  }
}
