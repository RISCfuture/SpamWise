import ArgumentParser
import SpamWiseCore

/// Headless IMAP filtering for one explicitly configured account.
@main
struct SpamWiseDaemon: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "spamwise-daemon",
    abstract: "Filter one IMAP account without the SpamWise app.",
    discussion: """
      The default command runs one bounded dry run. Classification can send bounded message \
      context to the selected provider; paid requests count toward the store's monthly spending \
      limit, if one is set.

      Without statePath in the configuration, every command uses the store the app shares and \
      prints each shared setting it changes. Validation is recorded for the daemon only: it never \
      changes the app's incoming route or transport. --model requires statePath, so the daemon \
      never changes the app's model.

      Mail a dry run previews counts as processed: live filtering that shares the store skips it. \
      No launch service is installed. SIGINT and SIGTERM cancel pending work. Secrets are never \
      arguments; providerCredentials can reference environment or login Keychain secrets. There is \
      no provider or credential fallback.
      """,
    subcommands: [RunCommand.self, ValidateCommand.self, ProbeCommand.self],
    defaultSubcommand: RunCommand.self
  )
}
