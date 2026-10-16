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
- Optional `rspamc` executes a separately installed program. Exclude that integration
  from the store variant rather than make store functionality depend on it. The
  core classifier and other evidence do not require it.
- Cloud-provider selection and Help currently describe data flow, but the store
  release should retain explicit, revocable provider-specific mail-sharing consent
  and gate requests before credentials/reservations. Include attachment/OCR text,
  correction examples and sensitive mail in the disclosure. Supplying an API key
  alone should not substitute for that permission.
- The privacy policy/support URLs, provider-retention disclosures, required-reason
  API manifest review and complete App Store metadata remain pending. Do not claim
  “data not collected” merely because the user supplies their own provider key.
- PCC is visible as an option but the app lacks its managed entitlement. The store
  release must either obtain and validate the grant or omit the unavailable option.
- Signed store export previously stopped at Distribution-key access. A successful
  Developer ID archive is not evidence of a signed store package or store acceptance.
- Pricing is undecided. Review the actual business model; do not assume any exception
  automatically covers third-party AI credits. Offline rules/review remain usable
  without a provider key. A reviewer needs a complete demonstrable flow using
  synthetic mail and appropriate review access, without the owner's personal keys.

## Store-first release gates

1. Finish the runtime acceptance work and store-specific feature/consent/privacy gaps.
2. Produce and validate a correctly signed local App Store package with original
   entitlements; supply the Mail exception justification and issue reference.
3. Prepare final policy/support links, pricing, screenshots and review instructions.
4. Submit only as a deliberate release step, then handle Apple's actual decision.

The fallback authorized by the owner is **GitHub Releases with
`~/Repositories/Libraries/GitHubUpdateChecker`**, if App Store distribution proves
unsuitable. The checkout has no Git remote yet. No alternate updater has been added,
no repository/hosting address has been invented, and no store upload has occurred.
See [packaging preparation](app-store.md) and [lifecycle](lifecycle.md).
