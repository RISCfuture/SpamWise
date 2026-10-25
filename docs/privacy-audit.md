# Privacy data inventory

This is the source and artifact inventory behind the public [privacy policy](privacy.md)
and the privacy manifests, `SpamWise/PrivacyInfo.xcprivacy` (both editions) and
`MailExtension/PrivacyInfo.xcprivacy`. Change all four together whenever a provider,
evidence service, stored collection, dependency, export format or edition capability
changes. It is not an App Store Connect submission; open release work is in
[TODO.md](../TODO.md).

## Data-flow inventory

| Boundary | Data and control |
| --- | --- |
| Apple Mail | Bounded source/history reads and account-scoped actions through public Apple Events, with macOS Automation consent. No Mail database access or Full Disk Access |
| Mail extension | Returns no decision for any message and stores nothing; its manifest declares no collection |
| IMAP | Optional direct TLS connection to the configured server with the user's password (the headless daemon can also use an OAuth bearer token); bounded reads with `BODY.PEEK`, account-scoped moves and Review keywords |
| Contacts | Optional. Email addresses are matched locally and snapshotted in the App Group store, refreshed hourly while the app runs; whether a sender is a contact can appear in an authorized model request |
| SwiftData App Group store | Settings, rules, decisions, bounded retries/corrections/retained labels, learned signals, action claims, spending, sender/receipt history, the Contacts snapshot, and per-account Authentication-Results and ARC-Authentication-Results receiving-server observations (up to 50 messages and 16 servers) plus the trusted servers the user confirms |
| App Group files | `rdap-cache.json`: registration ages for up to 2,048 domains, kept seven days, or one hour when unknown |
| Keychain (shared group) | Provider API keys, the Spamhaus HTTPS query key and IMAP credentials. Excluded from backups, settings and default diagnostics |
| Claude | Messages API through the Claude SDK's default URL session, user's key, per-request deadline and response-token cap; SDK/app/OS information in User-Agent; no SpamWise proxy |
| OpenAI | Responses API, user's key, `store: false`, bounded request, no hosted tools or background response polling |
| Gemini | `generateContent`, user's key, bounded request; no account billing/contract eligibility detection |
| Model request content | Sender address and display name, subject, shortened body, enabled attachment/OCR text, evidence, filtering preferences and the user-chosen number of similar correction excerpts (five by default, up to 20) quoted by domain, from the same account or, for imported reviewed examples, any account. Requires per-provider mail-sharing consent; blocked in local mode |
| RDAP | Opt-in sender-domain lookup through IANA bootstrap data and the listed registration services |
| Spamhaus DBL, public DNS | Opt-in, terms acknowledged. In-process DNS questions for From, Reply-To, Return-Path and link domains (at most five per message) sent only to the configured resolver; available in both editions |
| Spamhaus DBL, HTTPS | Opt-in, terms acknowledged. Same domains sent to `apibl.spamhaus.net` with the user's query key in the Authorization header; no redirects, cookies, credential persistence or cache |
| Rspamd | Opt-in fixed-loopback HTTP to `127.0.0.1:11333` with up to 2 MB of raw mail; the scanner's own configuration controls downstream traffic, logging and learning. No external executable is run |
| OCR/text attachments | Local decoding; no remote image loads, macro execution or antivirus claim |
| GitHub | Download edition only: scheduled and manual release checks against `RISCfuture/SpamWise`, and a user-initiated disk-image download. The App Store edition does not link the checker |
| Support/export | User-initiated files or email; default diagnostics exclude keys and message content; raw/content exports require deliberate selection |

Remote requests can include other people's personal data. Permission to share mail
does not establish that a particular provider account or use is legally suitable.

## App Privacy answers

App Privacy answers include third-party practices; local storage and user-supplied
credentials do not make the app "data not collected". Apple explains the
[questionnaire's collection and third-party scope](https://developer.apple.com/app-store/app-privacy-details/).
The manifest and App Store Connect answers declare:

| Data type | Purpose | Linked | Tracking | Basis |
| --- | --- | --- | --- | --- |
| Emails or Text Messages | App Functionality | Yes | No | Message context sent to the selected provider under the user's own key; domains sent to optional evidence services |
| Other User Content | App Functionality | Yes | No | Filtering preferences and correction excerpts sent with each request |

Contacts are matched locally and not transmitted as a list. Local activity, estimated
costs and retry state are not analytics collection.

## Required-reason APIs and dependencies

The app uses standard UserDefaults and SwiftUI AppStorage for app-owned preferences;
UI fixtures use isolated test suites. Persistent App Group state uses SwiftData, not
an App Group defaults suite, so the manifest declares
`NSPrivacyAccessedAPICategoryUserDefaults` with `CA92.1` only, and not `1C8F.1`. See
Apple's [required-reason categories](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).

Source searches covered the app, extension, core modules and the pinned
ClaudeForFoundationModels revision for UserDefaults, timestamp attributes,
`stat`/`fstat`, system uptime, disk-space access and absolute Mach time, with no
other direct call site found. The SDK's `Telemetry.swift` builds a User-Agent from
SDK, app, Swift and OS versions; it is not a separate analytics transport. Repeat
the search, and an undefined-symbol inspection of the archived app, for every new
dependency (the download edition adds GitHubUpdateChecker, MarkdownUI and swift-log)
and before each submission. That targeted inventory can miss indirect framework
behavior; it does not replace Xcode's privacy report or Apple's validation. Do not
add unused reason codes as a substitute for understanding actual API use.

## Provider terms

The policy links directly to each provider's current terms. OpenAI's `store: false`
setting is not a zero-retention agreement. Anthropic's zero-retention eligibility is
not an account grant. Gemini's paid/unpaid and regional distinctions cannot be
inferred from a key. The Account consent disclosure links to each provider's data
terms and explains Gemini's unpaid-service limitation in English, Spanish and French;
it does not validate the user's contract or billing setup.
