# App Store feasibility — 2026-10-16

**Decision: pursue the Mac App Store first.** There is no established blanket
prohibition on this sandboxed Mail.app product. This is a source/code assessment,
not an App Review approval. Do not switch to external updates merely because an
exception needs review.

Apple's [Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
require sandboxed Mac apps using appropriate public APIs, self-contained packaging,
consent for login operation, and App Store updates (§2.4.5/2.5). They also require
an accessible privacy policy and explicit permission before sharing personal data
with third-party AI (§5.1). Pricing and service access need evaluation under §3.1;
API credentials should not be described as a SpamWise license key.

Apple's [temporary-exception documentation](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/AppSandboxTemporaryExceptionEntitlements.html)
permits requesting Apple Events exceptions with a necessity explanation and issue
reference in App Store Connect. Scripting access groups are preferred where suitable.
The presence of an exception is not proof of rejection; approval is discretionary.

## Findings in this checkout

- The app and extension enable App Sandbox, preserve their identifiers/App Group,
  use public MailKit/Apple Events APIs, and contain no external updater. Login
  registration is opt-in and quitting the app ends its monitoring task.
- The installed Mail dictionary exposes `com.apple.mail.compose` access groups.
  Existing-mail source, history, lookup and move operations lack a suitable narrow
  group. Replacing the exception with compose permission would break the product.
  Keep the exact `com.apple.mail` exception and explain its bounded use accurately.
- The `APP_STORE` variant disables optional `rspamc` execution and its configuration
  UI, including restored executable settings. The core classifier does not require it.
  An explicit fixed-loopback HTTP transport supports a separately configured local
  Rspamd service in either distribution. Signed sandbox probes establish connectivity;
  they do not establish App Review acceptance. Neither transport is required or
  enabled by default, and both are blocked in local-only mode.
- Provider-specific mail-sharing permission defaults off, including existing stores.
  Requests require consent before credentials/reservations and recheck it before
  paid requests. The disclosure includes attachment/OCR text, correction examples
  and sensitive mail. Supplying an API key does not grant mail-sharing permission.
  Domain-age lookups also require a separate opt-in to share sender domains.
- Privacy/support drafts, provider-retention disclosures, a targeted required-reason
  API audit and static pages are prepared. Public URLs, final privacy answers and
  complete App Store metadata remain pending. Do not claim
  “data not collected” merely because the user supplies their own provider key.
- The app lacks the managed PCC entitlement. The store variant omits that choice
  and rejects restored PCC settings without silently changing providers.
- A privacy manifest declares the app's own UserDefaults access with reason CA92.1.
  The [privacy audit](privacy-audit.md) records the source/dependency inspection
  and provider terms. Final artifact validation and publisher privacy answers remain
  release gates; the manifest is not an App Privacy questionnaire submission.
- A local store package now passes app/extension and installer signature checks
  using the existing Match identities. Authenticated store validation stops because
  the App Store Connect app record does not exist; this is separate from App Review.
- The app will be free, published by Tim Morgan (<tim@tim.codes>). Optional provider
  usage is paid directly to the provider; verify the complete review flow rather
  than assuming free app pricing resolves service-access requirements. Offline rules/review remain usable
  without a provider key. A reviewer needs a complete demonstrable flow using
  synthetic mail and appropriate review access, without the owner's personal keys.

## Store-first release gates

1. Finish the runtime acceptance work and store-specific feature/consent/privacy gaps.
2. Produce and validate a correctly signed local App Store package with original
   entitlements; supply the Mail exception justification and issue reference.
3. Publish the prepared static site under `docs/` at a confirmed repository/address,
   enter the confirmed free pricing, and finish screenshots and review access.
4. Submit only as a deliberate release step, then handle Apple's actual decision.

Direct distribution can coexist with the Mac App Store. Its selected update approach
is **GitHub Releases with
[GitHubUpdateChecker](https://github.com/RISCfuture/GitHubUpdateChecker)** 2.3.0 or
later, resolved as a remote package; it also remains the fallback if the store path
proves unsuitable. Track actual feature cuts and common acceptance gaps in the
[distribution ledger](distribution-differences.md). No alternate updater has been
added, no release hosting address has been invented, and no store upload has occurred.
See [packaging preparation](app-store.md) and [lifecycle](lifecycle.md).
