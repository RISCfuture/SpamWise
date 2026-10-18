# Mac App Store and direct distribution

Updated 2026-10-16. Keep this ledger current whenever distribution-specific code,
entitlements, packaging or review decisions change. Mac App Store preparation is
the current priority; a direct version may coexist rather than exist only as a
fallback. This is a product/code comparison, not a promise of App Review approval.

## Functionality and restrictions

| Capability | Mac App Store version | Direct version | Evidence and status |
| --- | --- | --- | --- |
| Optional local Rspamd | Fixed-loopback HTTP transport only, off by default | Fixed-loopback HTTP transport only, off by default | Neither edition runs an external `rspamc` executable. The loopback service is separately configured and optional in both editions; it is not bundled or installed by SpamWise. |
| Updates outside the store | The `SpamWise-MAS` target links no updater; updates come from the App Store | The `SpamWise-download` target links GitHubUpdateChecker for scheduled and manual checks against `RISCfuture/SpamWise` | The sandboxed app downloads a release's disk image for the user to install; the library never installs automatically into a sandboxed app. See [updating](updating.md). |
| Private Cloud Compute | Hidden and rejected | Hidden and rejected | Neither edition holds the managed entitlement, so neither offers the provider; a restored selection fails open with a prompt to choose another. |
| Mail source/history, selected-message actions and Inbox/Junk moves | Implemented; temporary Apple Events exception requires review | Implemented; settled generated-message moves verified for iCloud/Google | A review gate, not an excluded feature. If Apple rejects the necessary exception, record the actual scope and reassess viability before removing core Mail functionality. |
| CLI evaluator and headless executable | Separate developer tools, not bundled or installed as a background service by the app | Existing package executables; not currently packaged with the GUI release | No removed GUI functionality. Standalone IMAP expansion remains outside the Mail.app-only roadmap in both channels. |
| Launch at login and monitoring with windows closed | Opt-in, app-owned lifecycle | Same behavior | No current difference. Quitting the app stops its monitor; no always-running service is installed. |
| Claude/OpenAI/Gemini, on-device model, rules, learning, corpus, review, statistics and backups | Same implementation, subject to common runtime/quality gates | Same implementation and gates | No current feature exclusion. Provider mail-sharing consent and local-mode protection apply to both. |
| OCR, bounded text/HTML attachments and optional domain lookups | Same opt-in implementation | Same opt-in implementation | PDF/Office extraction and wider fixture acceptance remain common gaps, not store cuts. |
| Payments, licensing and service access | Free app; third-party provider access remains subject to store review | Free app | Publisher: Tim Morgan, <tim@tim.codes>. Optional API usage is billed by the provider. No paid app feature or licensing system is planned. |

Apple's [Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
§2.4.5 require sandboxing, self-contained packaging and store-based updates for
Mac App Store apps. The external-executable exclusion is our implementation choice
for that channel. Apple's [PCC eligibility](https://developer.apple.com/private-cloud-compute/)
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
[direct packaging](packaging.md). Neither channel has a new release published by
this assessment.

## Build separation

Each edition is its own app target with its own `App` struct, Info.plist and
entitlements: `SpamWise-MAS` (scheme `SpamWise (MAS)`) and `SpamWise-download`
(scheme `SpamWise (download)`). Both link the `SpamWise Common` framework, which
holds every view and the app model, and embed the same Mail extension. Only the
download target links GitHubUpdateChecker and injects the update checker that
shows the update controls, so no compile-time flag or command-line override
selects an edition. Both products are named `SpamWise.app` with the shared
bundle identity, so install only one edition at a time.
