# Mac App Store and direct distribution

Keep this ledger current whenever edition-specific code, entitlements, packaging or
review decisions change. The Developer ID download edition is the primary channel; the
Mac App Store edition depends on App Review granting the Mail Apple Events exception
(see [feasibility](app-store-feasibility.md)). This is a product and code comparison,
not a promise of App Review approval.

## Functionality and restrictions

| Capability | Mac App Store edition | Download edition | Notes |
| --- | --- | --- | --- |
| Optional local Rspamd | Fixed-loopback HTTP transport only, off by default | Fixed-loopback HTTP transport only, off by default | Neither edition runs an external scanner executable. The loopback service is separately configured and optional in both editions; it is not bundled or installed by SpamWise. |
| Updates outside the store | The `SpamWise-MAS` target links no updater; updates come from the App Store | The `SpamWise-download` target links GitHubUpdateChecker for scheduled and manual checks against `RISCfuture/SpamWise` | The sandboxed app downloads a release's disk image for the user to install; the library never installs automatically into a sandboxed app. See [updating](updating.md). |
| Private Cloud Compute | Hidden and rejected | Hidden and rejected | Neither edition holds the managed entitlement, so neither offers the provider; a restored selection fails open with a prompt to choose another. |
| Mail source/history, selected-message actions and Inbox/Junk moves | Same implementation; the temporary Apple Events exception needs App Review approval | Same implementation and entitlement | A review gate, not an excluded feature. If Apple refuses the exception, the store edition cannot move mail; reassess it as IMAP-only or drop it. |
| Optional Spamhaus DBL | Public DNS or keyed HTTPS, off by default | Same | Public DNS uses in-process resolver queries, so no subprocess or extra entitlement is involved. |
| IMAP account route | Selectable in Settings | Same | No live acceptance yet in either edition. |
| CLI evaluator and headless daemon | Separate package executables, not bundled or installed by the app | Same | No GUI functionality is removed. |
| Launch at login and monitoring with windows closed | Opt-in, app-owned lifecycle | Same behavior | No current difference. Quitting the app stops its monitor; no always-running service is installed. |
| Claude/OpenAI/Gemini, on-device model, rules, learning, corpus, review, statistics and backups | Same implementation, subject to common runtime/quality gates | Same implementation and gates | No current feature exclusion. Provider mail-sharing consent and local-mode protection apply to both. |
| OCR, bounded text/HTML attachments and optional domain lookups | Same opt-in implementation | Same opt-in implementation | PDF/Office extraction and wider fixture acceptance remain common gaps, not store cuts. |
| Payments, licensing and service access | Free; third-party provider access is subject to store review | Free | Publisher: Tim Morgan, <tim@tim.codes>. Optional API usage is billed by the provider. No paid feature or licensing system is planned. |

Apple's [Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
§2.4.5 require sandboxing, self-contained packaging and store-based updates for
Mac App Store apps. Apple's [PCC eligibility](https://developer.apple.com/private-cloud-compute/)
is a separate entitlement/distribution constraint. See the
[feasibility assessment](app-store-feasibility.md) for Mail exception and privacy
review requirements.

## Rules for dual releases

- Keep one shared implementation and explicit build capabilities. Test both variants;
  restored preferences must not bypass a channel's disabled capabilities.
- Keep fail-open behavior, no Trash/delete action, explicit cloud consent and spend
  limits identical. Direct distribution does not justify weakening those contracts.
- Preserve existing bundle IDs, App Group and Keychain identity. Plan for one active
  installation at a time unless simultaneous installation is separately designed
  and tested; two filters sharing state or registering the same Mail extension could
  interfere with each other.
- Verify channel switching, shared-state migration, login-item registration,
  extension registration and update ownership before claiming migration support.
  Switching channels must not reset spending or replay protection.
- Store builds must not offer direct binary updates. Direct releases require their
  own signed/notarized artifacts, verified updater and recovery tests. Review/signing
  acceptance is specific to each channel and artifact.
- Record any future restriction with the affected user workflow, the code switch,
  its actual policy/review basis, direct-version behavior and acceptance evidence.
  Keep proposed cuts distinct from cuts actually implemented.

See [lifecycle](lifecycle.md), [App Store packaging](app-store.md) and
[packaging](packaging.md).

## Build separation

Each edition is its own app target with its own `App` struct, Info.plist and
entitlements: `SpamWise-MAS` (scheme `SpamWise (MAS)`) and `SpamWise-download`
(scheme `SpamWise (download)`). Both link the `SpamWise Common` framework, which
holds every view and the app model, and embed the same Mail extension. Only the
download target links GitHubUpdateChecker and injects the update checker that
shows the update controls, so no compile-time flag or command-line override
selects an edition. Both products are named `SpamWise.app` with the shared
bundle identity, so install only one edition at a time.
