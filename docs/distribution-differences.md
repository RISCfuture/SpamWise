# Mac App Store and direct distribution

Updated 2026-10-16. Keep this ledger current whenever distribution-specific code,
entitlements, packaging or review decisions change. Mac App Store preparation is
the current priority; a direct version may coexist rather than exist only as a
fallback. This is a product/code comparison, not a promise of App Review approval.

## Functionality and restrictions

| Capability | Mac App Store version | Direct version | Evidence and status |
| --- | --- | --- | --- |
| Optional local Rspamd through an external `rspamc` executable | Disabled in settings and the shared pipeline by `APP_STORE`, including restored settings | Implemented as an opt-in; signed sandbox execution still needs acceptance | This is the current functional exclusion. It is our conservative packaging choice under Apple's self-contained-app requirements, not a recorded rejection. The main classifiers do not depend on it. |
| Updates outside the store | Updater dependency excluded from the `SpamWise` target; updates must use the App Store | `SpamWiseDirect` links the local GitHubUpdateChecker for manual stable-release discovery and a release-page link | No repository host is configured, so no checks run. Binary download/installation is not enabled: the library does not establish signature/identity verification or safe replacement. See [update acceptance](updating.md). |
| Private Cloud Compute | Hidden and rejected until the managed entitlement and eligible distribution are verified | Experimental selector exists, but no accepted Developer ID PCC capability | Not functionality sacrificed for MAS. Apple requires App Store distribution for production PCC; eligible testing channels are separate. Do not advertise direct PCC support from the presence of the selector. |
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

The shared `SpamWiseDirect` scheme builds the additional app target with
`SPAMWISE_DIRECT_UPDATES`. Only that target links the `GitHubReleaseDiscovery`
product from the local `../../Libraries/GitHubUpdateChecker` package. It uses the same app sources,
entitlements, bundle identity and Mail extension. Its product is
`SpamWiseDirect.app` to keep build/test products distinct; the bundle identity is
shared, so install only one channel at a time.

Use the existing `SpamWise` target and `APP_STORE` packaging commands for the
store. That target has no updater product dependency. Building `SpamWiseDirect`
with `APP_STORE` intentionally fails compilation. The direct dependency may still
be resolved when Xcode opens the project; resolution does not put it in the store
app. Validate the final store archive for updater symbols and resources before
submission, as described in [updating](updating.md).
