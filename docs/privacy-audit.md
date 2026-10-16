# Privacy release audit — October 16, 2026

This is a source and artifact review, not an App Store Connect submission or a
promise about every future provider configuration. The public-policy draft is
[privacy.md](privacy.md); the remaining publisher and review work is listed below.

## Data-flow inventory

| Boundary | Data and control |
| --- | --- |
| Apple Mail | Bounded source/history reads and account-scoped actions through public Apple Events; macOS consent; extension callbacks through MailKit |
| Contacts | Local address matching after permission; no full address-book upload; bounded relationship evidence can be part of an authorized model request |
| SwiftData/App Group | Settings, decisions, bounded retries/corrections/retained labels, learned signals, action claims and spending; local process-shared transactions |
| Keychain | Provider credentials; not included in portable state backups or default diagnostics |
| Claude | Messages API, explicit key, fresh bounded request; SDK/app/OS information in User-Agent; no SpamWise proxy |
| OpenAI | Responses API, explicit key, `store: false`, bounded request, no hosted tools or background response polling |
| Gemini | `generateContent`, explicit key, bounded request; no account billing/contract eligibility detection |
| RDAP | Opt-in sender-domain lookup using IANA discovery and registration endpoints |
| Spamhaus DBL | Opt-in domain queries through an explicitly configured resolver and acknowledged service terms |
| Rspamd | Explicit fixed-loopback HTTP or configured executable receives bounded raw mail; only executable transport is excluded by `APP_STORE`. Both default off and local-only mode blocks both. Scanner configuration controls downstream traffic/logging/learning and needs its own acceptance |
| OCR/text attachments | Local decoding; no remote image loads, macro execution or antivirus claim |
| GitHub | Direct variant only, manual configured release discovery; no repository currently configured; store product excludes discovery dependency |
| Support/export | User-initiated files or email; default diagnostics exclude keys and message content; raw/content exports require deliberate selection |

Remote requests can include other people’s personal data. Permission to share mail
does not establish that a particular provider account or use is legally suitable.
App Privacy answers must include relevant third-party practices rather than infer
“no collection” from local storage or user-supplied credentials. Apple explains the
[questionnaire’s collection and third-party scope](https://developer.apple.com/app-store/app-privacy-details/).

## Required-reason API and dependency inspection

The app source uses standard UserDefaults and SwiftUI AppStorage for app-owned
preferences. UI fixtures use isolated test suites. Persistent App Group state uses
SwiftData, not an App Group UserDefaults suite. The app manifest declares
`NSPrivacyAccessedAPICategoryUserDefaults` with `CA92.1` and tracking false.
There is no evidence in these call sites for adding `1C8F.1` just because the app
also has an App Group entitlement. See Apple’s
[required-reason categories](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).

Source searches covered app, extension, core modules and the pinned
ClaudeForFoundationModels revision `0262e1a766c461a4268dcec656eca95dd74cebf8` for
UserDefaults, timestamp attributes, `stat`/`fstat`, system uptime, disk-space access
and absolute Mach time. No additional direct call site in those categories was
found. The SDK’s `Telemetry.swift` constructs a User-Agent from SDK, app, Swift
and OS versions; it is not a separate analytics transport. The SDK is not assumed
to have zero metadata merely because SpamWise has no tracking integration.

An undefined-symbol inspection of the installed optimized app at `f7635ac` found
NSUserDefaults/AppStorage, consistent with the manifest. The extension had no
matching required-reason symbol in the searched set. This targeted inventory can
miss indirect framework behavior or dynamically resolved selectors; it is not a
replacement for Xcode’s privacy report and Apple’s validation of the final release.
The final local store package includes this privacy manifest, preserves the
App Group/sandbox entitlements, and contains no direct-updater symbol. Server
validation still stops at the missing app record. Recheck dependencies and the
final release artifact before submission. Do not add
unused reason codes as a substitute for understanding actual API use.

## Provider review and product disclosure

Provider source documents were checked on October 16, 2026. The policy draft links
directly to their current terms. OpenAI’s `store: false` setting does not constitute
a zero-retention agreement. Anthropic’s ZDR eligibility is not an account grant.
Gemini’s paid/unpaid and regional distinctions cannot be inferred from a key.
The Account consent disclosure now links to each provider’s data terms and explains
Gemini’s unpaid-service limitation in English, Spanish and French. It does not
pretend to validate the user’s contract or billing setup.

## Remaining release work

- Confirm the publisher’s actual provider arrangements and final App Privacy
  questionnaire answers, including linkage and any retention exceptions.
- Select the hosting repository, publish the policy/support pages, and enter their
  real URLs. Do not fabricate a public address from the app’s bundle ID.
- Generate the final archive privacy report and complete store validation after
  creating the App Store Connect app record. Local distribution signing now passes;
  see [the exact validation result](app-store.md#verified-local-package-and-current-validation-gate).
- Provide App Review’s Mail exception/issue reference and adequate reviewer access.
- Reassess this inventory whenever a provider, telemetry path, dependency, export
  format or distribution capability changes.

No account setting, provider retention control, privacy label or public website was
changed by this review.
