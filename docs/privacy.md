# SpamWise privacy policy

Publication draft · Updated October 18, 2026

SpamWise is developed by Tim Morgan. For privacy questions or requests, contact
[tim@tim.codes](mailto:tim@tim.codes). This page describes the current implementation
of both editions: the downloadable edition and the Mac App Store edition. Neither has
been published yet.

## Mail and local storage

SpamWise reads selected mail and bounded mailbox pages through Apple Mail, with
macOS Automation permission. If you configure an IMAP account instead, SpamWise
connects directly to that server over TLS with the credential you supply. It uses
message text and metadata to suggest or apply Inbox, Review and Junk decisions. It
does not delete mail or move it to Trash. Apple Mail and your mail servers continue to
operate under their own terms.

The following stay on your Mac, in SpamWise's containers:

- settings, sender and content rules, decisions, correction examples, retry data,
  action records and spending records;
- a snapshot of your Contacts' email addresses, when you allow Contacts access,
  refreshed hourly while SpamWise runs;
- sender and receipt history built from bounded Sent and Inbox pages;
- for each account, the receiving-server names seen in the Authentication-Results
  headers of up to 50 recent messages, used to work out which servers' results to
  trust, and the servers you choose to trust;
- a cache of domain registration ages, when domain-age lookups are on: up to 2,048
  domains, kept seven days, or one hour when the age was unknown;
- additional bounded message text, only when you turn on learning or reviewed-content
  retention.

Credentials are stored only in Keychain: your model-provider API keys, a Spamhaus query
key and IMAP passwords or OAuth tokens. Settings → Accounts → Keys and passwords lists
each saved credential with Remove, and Remove All SpamWise Keys and Passwords… deletes
every one; Forget Connection… deletes the IMAP password. Portable backups are encrypted
with a recovery key that you keep separately, and they exclude credentials. Exports can contain
personal mail information, depending on the export you choose; keep those files
private.

Contacts matching happens on the Mac; your address book is never uploaded as a list.
Whether a sender is a contact can still appear as evidence in a model request when you
allow mail sharing.

## Optional model providers

Cloud classification requires your own API key and a separate permission for the
selected provider. Each request can include the sender's address and display name, the
subject, shortened message text, available evidence such as authentication results and
link domains, your filtering preferences, and up to five earlier corrections from the
same account, quoted with the sender's domain rather than address. Enabled attachment
text extraction and image OCR add text to that context. Email can contain personal,
confidential or sensitive information about you and other people. SpamWise sends
requests directly to the selected provider using your API key; Tim Morgan does not
operate a relay for these requests.

- **Anthropic Claude:** the API's commercial retention and training terms apply.
  Standard API inputs and outputs are generally deleted within 30 days, with
  documented exceptions. A zero-retention arrangement is separate; SpamWise does
  not enable or verify it. See [Anthropic's retention policy](https://privacy.claude.com/en/articles/7996866-how-long-do-you-store-my-organization-s-data).
- **OpenAI:** SpamWise uses the Responses API with `store: false`. This disables
  normal stored-response state, but does not itself disable abuse monitoring or
  every form of retention. OpenAI documents default abuse-monitoring retention of
  up to 30 days, with exceptions and eligible account controls. See
  [OpenAI's data controls](https://developers.openai.com/api/docs/guides/your-data).
- **Google Gemini:** paid and unpaid service terms differ, with regional provisions.
  Unpaid-service terms permit model improvement and human review and instruct users
  not to submit personal or confidential information. Confirm which terms apply
  before enabling mail sharing; SpamWise cannot verify your project's billing status
  or contractual terms. See [Gemini's terms](https://ai.google.dev/gemini-api/terms).

Providers receive ordinary connection and account information such as your IP
address and API authentication. The Claude SDK also sends app, SDK and operating
system version information in its request header. Provider terms, account settings,
retention exceptions and service locations govern their processing. Your provider
may charge for requests separately from the free app.

You can revoke mail-sharing permission in Settings → Classifier, under Mail sharing.
Revocation stops new requests; it cannot recall requests already sent or delete a provider's records.
Contact the provider for its deletion and account-control options.

## On-device processing and optional evidence

The on-device model performs inference on the Mac when available. Explicit local
mode also blocks SpamWise's cloud providers and outbound evidence lookups. Merely
selecting the on-device model does not turn off separately enabled evidence services.
Local mode does not prevent Apple Mail or macOS from performing their own network
operations. Private Cloud Compute is not offered.

Every evidence service below is off by default, requires its own opt-in and is
blocked in local mode. None of them receives message text, full email addresses or
URL paths.

- **Domain-age lookups** send sender domains to the registration-data (RDAP) services
  that IANA lists for each domain.
- **Spamhaus reputation checks** send the sender, Reply-To, Return-Path and link
  domains, at most five per message, either as DNS questions to the resolver you
  configure or directly to Spamhaus over HTTPS. HTTPS uses your own query key from
  Keychain, sent in the request header. Both require acknowledging Spamhaus's terms.
  SpamWise keeps no Spamhaus results beyond the message's own evidence.
- **Local Rspamd scanning** sends up to 2 MB of raw message data to a scanner you run
  at `127.0.0.1:11333`. That scanner's configuration determines any further
  processing, including its own outbound lookups.

Image OCR and supported text-attachment extraction run locally and do not load remote
images or execute attachments.

## Diagnostics, updates and your choices

SpamWise contains no advertising, analytics or tracking integration. Activity and
usage statistics are local. A redacted diagnostics export omits keys and message
content by default; inspect any file before sharing it. Emailing support sends your
message and any attachments you choose to Tim Morgan through email services.

The downloadable edition checks GitHub Releases for a newer version on the schedule
you choose in Settings (hourly, daily, weekly or never) and when you ask. The request
exposes normal network information to GitHub, without mail content or credentials.
When you choose to update, it downloads the release's disk image for you to install.
The App Store edition contains no update checker; the App Store keeps it current.

The Mail extension makes no decisions and stores nothing; it leaves every message to
Mail.

Pause stops new processing. Dry run prevents mail actions but can still send
authorized model and evidence requests. Quitting SpamWise stops its background
monitor. You can forget retained examples, remove rules, revoke permissions, remove
saved keys and passwords in Settings, or remove the app's stored data. See [support](support.md) and
[complete removal instructions](lifecycle.md). Removing the app alone leaves its data
and Keychain credentials for reinstall.

This policy is reviewed whenever data flows or provider terms change; the
[data inventory](privacy-audit.md) lists each flow. The published version carries its
revision date above.
