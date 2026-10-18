# IMAP and headless operation

SpamWise can access an explicitly configured IMAP account independently of Apple
Mail or another desktop client. No credentials are read from Mail's databases.
This route has offline protocol coverage; live TLS authentication and disposable
moves remain pending because no IMAP credentials have been supplied.

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

The default port is 993 with implicit TLS. Alternative ports still use TLS;
plaintext, STARTTLS downgrade and certificate-validation overrides are absent.
An optional `oauthBearer: true` selects OAuth bearer authentication. The server
must advertise both `AUTH=OAUTHBEARER` and `SASL-IR`. Token issuance and refresh
belong to the caller; SpamWise never invents or refreshes an OAuth grant.

Instead of `environment`, set `keychainService` and `keychainAccount` to an
existing login Keychain generic-password item. Only references belong in JSON;
unknown fields, including inline passwords, are rejected. Resolve environment
secrets only for the consuming process, for example through an existing
1Password environment. Never put secret values in command arguments or logs.

Omit `statePath` to use the signed app's App Group store. An unsigned CLI may
require an explicit private state path and has its own settings and action
validation. For unsigned operation, `providerCredentials` supplies references
keyed by exactly `claude`, `openAI`, or `gemini`. Each reference accepts either
`environment` or the pair `keychainService`/`keychainAccount`; inline keys,
unknown providers, OAuth flags, and references for Apple's keyless backends are
rejected. The selected paid provider must have its own reference. No credential
is reused between providers, and missing references or secrets fail open without
fallback. Keychain reads do not request interactive authentication.

Omitting `providerCredentials` preserves the signed app's shared Keychain lookup.
An unsigned standalone executable should supply explicit environment or login
Keychain references for paid providers. Apple on-device and PCC models need no
API key; PCC still requires Apple's managed entitlement and runtime availability.

Paid provider calls count toward the selected state store's monthly spending, the
same ledger the app shows under Usage and spending. Each request first counts its
largest possible cost, then its measured cost; requests the provider could not
have billed are refunded. If the user has set a monthly limit, a request that
would exceed it is not sent and its message stays unclassified. A private
`statePath` keeps separate monthly accounting with no limit until one is set. Dry
run still permits paid model calls.

## Read-only check and dry run

Build the `spamwise-daemon` Swift package product using the repository's isolated
build instructions. The executable's `--help` lists all options.

```sh
spamwise-daemon --config imap.json --validate
spamwise-daemon --config imap.json --once --limit 20
spamwise-daemon --config imap.json --once --model claude-haiku-5-5 --limit 20
spamwise-daemon --config imap.json --poll-seconds 60 --limit 20
```

`--model` explicitly chooses `claude-haiku-5-5`, `claude-sonnet-5-5`,
`claude-opus-5-5`, `gpt-5.4-mini`, `gemini-3.8-flash`, `apple-on-device`, or
`apple-private-cloud-compute`. It persists only the provider/model selection when
changed, invalidating stale classification retries through the ordinary settings
transaction. Other settings and action gates remain in force. Without the flag,
the selected store's existing model is used (Haiku for a fresh store). The flag
cannot be combined with `--validate` or `--probe`, and unsupported models fail
before connecting to IMAP.

`--validate` authenticates, discovers mailbox roles and examines Inbox. It never
fetches message bodies, marks messages read or moves messages. When the server
supports `UID MOVE` and designates a unique Junk mailbox, it records validation
for the exact account ID, host, port and username and selects the IMAP route in
the shared settings; otherwise it revokes any validation recorded for that
endpoint. It never turns off dry run.
The default run is a dry run. On a fresh store, and after a UIDVALIDITY change, the
first run records the highest existing UID as the start boundary and reads nothing;
later runs process only new mail above it. The highest UID comes from `UIDNEXT`, or
from the newest message when the server omits `UIDNEXT`. Mail that arrives after the
last run but before a UIDVALIDITY change falls below the new boundary and is not
filtered automatically. IMAP has no preview or refilter for mail below the boundary;
the older-mail preview in Settings covers Apple Mail accounts only. Dry run
suppresses mail actions but may send bounded message context to the explicitly
selected provider. Polling accepts intervals from 60 to 3,600 seconds and skips
previously processed identities.

A dry run counts the mail it previews as processed. Live filtering that shares the
store, including the app, then skips that mail instead of acting on it. While the
app filters live, give dry-run polling its own `statePath`.

Activity shows decision reasons in the viewer's language. Mail action failures are
saved as text in the language of the process that recorded them, so failures the
daemon records, having no string catalog, read in English.

Each run first reads every message above the highest UID already read, oldest first,
up to five pages and the 4 MB byte budget; the rest resumes on the next run. Once new
mail is caught up, the run reads one persisted backfill page that restarts after
reaching the boundary or the newest 10,000 messages. That progress is saved only
after every message the run read has been processed, so mail from a cancelled,
failed or paused run is read again as new mail. While filtering is paused, runs read
nothing. Action-enabled polling also processes due classification retries for the
configured account. Mailbox mutations can defer a message until the next sweep.
Polling does not use IMAP IDLE. SIGINT and SIGTERM cancel pending work. Nothing
installs a launch daemon or enables automatic startup.

## Optional disposable probe and actions

Validation comes from `--validate`, or from a passing read-only check in the app
for the same endpoint. The probe is an optional end-to-end move test. To run it,
place a disposable message whose subject starts with `[SpamWise Probe]` in Inbox
and obtain its current Inbox UID from your IMAP tooling; an Apple Mail local
message ID is not an IMAP UID. SpamWise neither sends nor deletes the message:
it never sends mail from your account, and it exposes no Trash or delete
operation, so you supply the message and delete it afterward.

```sh
spamwise-daemon --config imap.json --probe 123
```

The probe checks exact content and UIDVALIDITY, moves only that UID to the unique
server-designated Junk mailbox, verifies its new identity using COPYUID, then
moves and verifies it back in Inbox. Each move changes the UID. Failure or a
missing UID mapping stops the probe; uncertain moves are never automatically
reversed or retried. Inspect the disposable message manually if the probe fails.
A verified restoration also records validation for the exact endpoint. Neither
the probe nor `--validate` changes the shared dry-run setting.

```sh
spamwise-daemon --config imap.json --once --actions
```

Actions require the explicit flag, recorded endpoint validation, the IMAP route,
an unpaused pipeline and dry run disabled in the shared settings. The pipeline
persists explanations and action claims before dispatch. An unconfirmed outcome
retains its claim. Validation for another endpoint or Apple Mail does not grant
IMAP authorization. Orange flag colors are not portable in IMAP; Review remains
without that annotation when this route rejects the unsupported action.

## Protocol limits and interoperability

Each operation uses a fresh TLS session capped at 30 seconds. Reads are bounded
to 64 KiB chunks and protocol lines, eight literals per response, 12 nested lists,
4,096 tokens per response, 2,048 responses per command and 4.2 MB per command.
Message literals are capped at 2 MB. A recent/history page includes at most 100
messages and 4 MB of content. Oversized, malformed, ambiguous, interrupted or
unsupported responses fail open.

Mailbox roles come from SPECIAL-USE rather than guessed localized names. Multiple
Junk/Sent designations are rejected. Trash and nonselectable roles are excluded.
Mailbox wire names support ASCII and IMAP modified UTF-7, quoted escapes and
literals; unsupported non-ASCII wire names are rejected. UIDVALIDITY and UID,
mailbox and account form the stable namespace. BODY.PEEK avoids setting Seen.
History imports only bounded Sent replies as partial history, never incoming
mail's own claims as proof of trust.

Only server-supported UID MOVE is used. There is no COPY/STORE Deleted/EXPUNGE
fallback, mailbox creation or Trash/delete command. A tagged success without a
matching COPYUID mapping is retained as an uncertain outcome.

The implementation follows [IMAP4rev2](https://www.rfc-editor.org/rfc/rfc9051.html),
[SPECIAL-USE](https://www.rfc-editor.org/rfc/rfc6154.html),
[UID MOVE](https://www.rfc-editor.org/rfc/rfc6851.html) and
[OAuth SASL](https://www.rfc-editor.org/rfc/rfc7628.html).
The reviewed [SwiftNIO IMAP library](https://github.com/apple/swift-nio-imap)
provides a broader grammar but labels itself unsuitable for production and does
not supply this adapter's bounded-input contract. SpamWise uses a deliberately
restricted parser and system Network.framework TLS; unsupported grammar is
rejected rather than interpreted permissively.
