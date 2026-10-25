# IMAP and headless operation

SpamWise can filter an explicitly configured IMAP account independently of Apple
Mail, either from the app (Settings → Accounts) or headlessly with
`spamwise-daemon`. No credentials are read from Mail's databases. The route is built
on [swift-nio-imap](https://github.com/apple/swift-nio-imap) and has offline protocol
coverage only; live acceptance is tracked in [TODO.md](../TODO.md).

In the app, set Settings → Accounts → Mail connection to IMAP and confirm Switch to
IMAP, which turns dry run on; each connection keeps its own mailbox check. **Save
Connection** stores the password in the shared Keychain (the app signs in with a
password only; the daemon also accepts an OAuth token), and **Check
Connection** performs the validation described below for the app. **Forget
Connection…** deletes that credential, revokes the app's validation of the endpoint
and returns to Apple Mail with dry run on. The rest of this page describes the daemon.

## Configuration

Use a JSON file containing endpoint settings and a secret reference:

```json
{
  "account": {
    "id": "imap:personal",
    "host": "imap.example.com",
    "username": "user@example.com"
  },
  "credential": {
    "environment": "SPAMWISE_IMAP_PASSWORD"
  },
  "providerCredentials": {
    "claude": { "environment": "ANTHROPIC_API_KEY" },
    "openAI": { "environment": "OPENAI_API_KEY" },
    "gemini": { "environment": "GEMINI_API_KEY" }
  },
  "statePath": "/absolute/private/path/SpamWise.store"
}
```

The default port is 993 with implicit TLS through Network.framework, which verifies
the certificate chain and host name. Alternative ports still use TLS; plaintext,
STARTTLS and certificate-validation overrides are absent. An optional
`"oauthBearer": true` in `credential` selects OAuth bearer authentication instead of
`LOGIN`. The server
must advertise both `AUTH=OAUTHBEARER` and `SASL-IR`. Token issuance and refresh
belong to the caller; SpamWise never invents or refreshes an OAuth grant.

Instead of `environment`, set `keychainService` and `keychainAccount` to an
existing login Keychain generic-password item. The item must trust the
`spamwise-daemon` executable, or the first read may show a Keychain access prompt
that the run waits on. Create it with the daemon in its access list, for example
`security add-generic-password -s <service> -a <account> -T <path to spamwise-daemon> -w`,
which asks for the password instead of taking it as an argument. Run `validate`
once while attended so any remaining prompt can be answered; unattended runs
should prefer environment references, which never prompt. Only references belong
in JSON; unknown fields, including inline passwords, are rejected. Resolve
environment secrets only for the consuming process, for example through an
existing 1Password environment. Never put secret values in command arguments or
logs.

Omit `statePath` to use the signed app's App Group store. An unsigned CLI may
require an explicit private state path and has its own settings and action
validation. For unsigned operation, `providerCredentials` supplies references
keyed by exactly `claude`, `openAI`, or `gemini`. Each reference accepts either
`environment` or the pair `keychainService`/`keychainAccount`; inline keys,
unknown providers, OAuth flags, and references for Apple's keyless backends are
rejected. The selected paid provider must have its own reference. No credential
is reused between providers, and missing references or secrets fail open without
fallback. Login Keychain references for providers need the same access list as
the IMAP credential.

Omitting `providerCredentials` preserves the signed app's shared Keychain lookup.
An unsigned standalone executable should supply explicit environment or login
Keychain references for paid providers. The Apple on-device model needs no API key.

Paid provider calls count toward the selected state store's monthly spending, the
same ledger the app shows under Usage and spending. Each request first counts its
largest possible cost, then its measured cost; requests the provider could not
have billed are refunded. If the user has set a monthly limit, a request that
would exceed it is not sent and its message stays unclassified. A private
`statePath` keeps separate monthly accounting with no limit until one is set. Dry
run still permits paid model calls.

## Commands

Build the `spamwise-daemon` package product (`swift build --package-path SpamWiseCore
--product spamwise-daemon`). It has three subcommands; `run` is the default, and
`--help` on each lists its options.

```sh
spamwise-daemon validate --config imap.json
spamwise-daemon run --config imap.json --limit 20
spamwise-daemon run --config imap.json --model claude-haiku-5-5 --limit 20
spamwise-daemon run --config imap.json --poll-seconds 60 --limit 20
spamwise-daemon probe --config imap.json 123
spamwise-daemon run --config imap.json --actions
```

### Validation

`validate` authenticates, discovers mailbox roles and examines Inbox. It never
fetches message bodies, marks messages read or moves messages. When the server
supports `UID MOVE` and designates a unique Junk mailbox, it records daemon
validation for the exact account ID, host, port and username and adds the account to
the store's validated accounts; otherwise it revokes the daemon's validation, which
turns dry run back on when no validated account remains. Validation is scoped: the
daemon's and the app's validations of the same endpoint are recorded separately, and
neither authorizes the other. It never changes the app's incoming route or transport,
and it prints every shared setting it changed.

### Sweeps

`run` sweeps once, or every `--poll-seconds` (60 to 3,600). `--limit` sets the page
size, 1 to 100. Without `--actions` the run is a dry run; it may still send bounded
message context to the selected provider.

`--model` chooses `claude-haiku-5-5`, `claude-sonnet-5-5`, `claude-opus-5-5`,
`gpt-5.4-mini`, `gemini-3.8-flash` or `apple-on-device`, and requires a `statePath`:
the daemon will not change the model in the store it shares with the app. It
persists only the provider/model selection, invalidating stale classification
retries through the ordinary settings transaction. Without it, the store's existing
model is used (Haiku for a fresh store).

On a fresh store, and after a UIDVALIDITY change, the first run records the highest
existing UID as the start boundary and reads nothing; later runs process only new
mail above it. The highest UID comes from `UIDNEXT`, or from the newest message when
the server omits `UIDNEXT`. Mail that arrives after the last run but before a
UIDVALIDITY change falls below the new boundary and is not filtered automatically.
IMAP has no preview or refilter for mail below the boundary.

Each run first reads every message above the highest UID already read, oldest first,
up to five pages and the 4 MB byte budget; the rest resumes on the next run. A run
scans at most the newest 2,000 messages for new mail, so a burst deeper than that leaves
its older part to a persisted backfill. Once new mail is caught up, each run reads one
backfill page, newest first, skipping without download the mail already read, until
the backfill reaches the mail read before the burst or the newest 10,000 messages; it
then stops until another burst. That progress is saved only after every message the
run read has been processed, so mail from a cancelled, failed or paused run is read
again. Otherwise each message is read once. While filtering is paused, runs read
nothing. Runs also maintain bounded Sent history for reply evidence, at most every 15
minutes, and action-enabled runs process due classification retries for the configured
account.

A dry run records the decisions it previews without moving mail. Because runs don't
read a message again, mail previewed during a dry run stays where it is when filtering
goes live, and rule, setting or correction changes make no new provider requests for
it. Dry-run polling that shares the store and account with live IMAP filtering,
including the app's, therefore leaves the mail it reads unfiltered; give it its own
`statePath` to keep them apart.

In poll mode a failed sweep is logged with its category and retried after a delay
that doubles from the poll interval up to an hour. The daemon exits on configuration
errors, after three consecutive authentication failures, or on SIGINT/SIGTERM, which
cancel pending work. Polling does not use IMAP IDLE. Nothing installs a launch daemon
or enables automatic startup.

Activity shows decision reasons in the viewer's language. Mail action failures are
saved as text in the language of the process that recorded them, so failures the
daemon records read in English.

### Actions and the disposable probe

`run --actions` requires daemon validation of this exact endpoint, an unpaused
pipeline and dry run disabled in the store's settings. The pipeline persists
explanations and action claims before dispatch; an unconfirmed outcome retains its
claim. Any failure before a mail command is sent is reported as an action not
attempted, so the message stays where it was and nothing is claimed as moved.

Junk moves use `UID MOVE` to the server-designated Junk mailbox. Review is stored as
the `$SpamWiseReview` keyword, or `\Flagged` where the mailbox admits no new keywords.
Clearing Review removes the keyword, but removes `\Flagged` only where SpamWise set it:
a message the user had already flagged keeps its flag. A message SpamWise moved to Junk that
later reappears in Inbox was rescued in another client: SpamWise records it as an
implicit Good correction, which also marks the sender as wanted, and never junks it
again.

`probe` is an optional end-to-end move test. Place a disposable message whose
subject starts with `[SpamWise Probe]` in Inbox and pass its current Inbox UID (an
Apple Mail local message ID is not an IMAP UID). SpamWise neither sends nor deletes
the message: you supply it and delete it afterward. The probe checks exact content
and UIDVALIDITY, moves only that UID to Junk, verifies its new identity using
COPYUID, then moves and verifies it back in Inbox. Each move changes the UID. Failure
or a missing UID mapping stops the probe; uncertain moves are never automatically
reversed or retried, so inspect the message manually if the probe fails. A verified
restoration records daemon validation; the probe never changes the dry-run setting.

## Protocol limits and interoperability

Each connection closes 30 seconds after it opens, whatever it is doing, and the
operation it interrupts fails as timed out; consecutive operations reuse a session
opened within the last 10 seconds. A sweep starts no new message fetch within 5
seconds of the cutoff, after its first, and keeps the new mail it has read, so a
slow link makes progress across runs instead of repeating the same batch.
Responses are parsed by swift-nio-imap with at most 16 message attributes per
fetch, 8,192 buffered responses, 2,048 responses and 4.2 MB per command. Message
literals are capped at 2 MB. A page includes at most 100 messages and 4 MB of
content. `RFC822.SIZE` is only a hint for these budgets, since servers such as
Exchange report estimates: the fetched literal's own length counts. A message
whose literal exceeds 2 MB stays unclassified like other oversized mail, and the
sweep ends there with its progress past that message. Oversized, malformed,
ambiguous, interrupted or unsupported responses fail open. Passwords may contain
any characters except NUL, CR and LF, and are sent as literals when they are not
plain ASCII.

Mailbox roles come from SPECIAL-USE rather than guessed localized names. Multiple
Junk/Sent designations are rejected. Trash and nonselectable roles are excluded.
UIDVALIDITY and UID, mailbox and account form the stable namespace. `BODY.PEEK`
avoids setting Seen. History imports only bounded Sent replies as partial history,
never incoming mail's own claims as proof of trust.

Only server-supported `UID MOVE` is used. There is no COPY/STORE Deleted/EXPUNGE
fallback, mailbox creation or Trash/delete command. A tagged success without a
matching COPYUID mapping, or whose message can't then be verified at its
destination, is retained as an uncertain outcome.

The implementation follows [IMAP4rev2](https://www.rfc-editor.org/rfc/rfc9051.html),
[SPECIAL-USE](https://www.rfc-editor.org/rfc/rfc6154.html),
[UID MOVE](https://www.rfc-editor.org/rfc/rfc6851.html) and
[OAuth SASL](https://www.rfc-editor.org/rfc/rfc7628.html). Dependencies are pinned in
`SpamWiseCore/Package.swift`: swift-nio-imap 0.4.0, swift-nio 2.103.0 and
swift-nio-transport-services 1.28.0, all Apache-2.0 (see [CREDITS.md](../CREDITS.md)).
swift-nio-imap 0.4.0 accepts a lone CR after a literal's `{size}` as a complete line
ending, so SpamWise holds back a chunk's trailing CR until the following bytes arrive.
