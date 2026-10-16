# App Store feasibility

**Decision: Developer ID is the primary channel; the Mac App Store edition is
secondary and depends on one App Review decision.** SpamSieve, the closest comparable
Mail filter, also ships outside the store. This is a source and code assessment, not
an App Review approval.

## The deciding risk: the Mail Apple Events exception

Every SpamWise action reaches Mail through Apple Events under
`com.apple.security.temporary-exception.apple-events` for `com.apple.mail`: history
import, message lookup, Junk and Inbox moves, Review flags and read status. Both
editions use it. Guideline 2.4.5(i) limits modifying other apps' data, temporary
exceptions are granted case by case, and Mail's scripting dictionary exposes only a
`com.apple.mail.compose` access group, which covers none of these operations.
Replacing the exception with compose access would break the product.

The Mail extension cannot stand in. MailKit messages carry no account identity
SpamWise can trust and MailKit offers no arbitrary-mailbox move, so the extension
returns no decision for any message. A store build without the exception would
therefore move no mail and would also invite a guideline 4.2 minimum-functionality
rejection.

So the store edition waits on an early exception decision, sought with the drafted
[justification](app-review-notes.md) before any further store polish. If Apple refuses
or limits it, the options are an IMAP-only store build (IMAP needs only the network
client entitlement, but has had no live acceptance) or no store edition at all.
Apple's [temporary-exception documentation](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/AppSandboxTemporaryExceptionEntitlements.html)
asks for a necessity explanation and an issue reference in App Store Connect and
prefers scripting access groups where the target offers a suitable one.

## Other guideline requirements

Apple's [Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
require sandboxed Mac apps using appropriate public APIs, self-contained packaging,
consent for login operation and App Store updates (§2.4.5/2.5). They also require an
accessible privacy policy and explicit permission before sharing personal data with
third-party AI (§5.1). Pricing and service access need evaluation under §3.1; API
credentials should not be described as a SpamWise license key.

How the code meets them:

- Both editions and the extension enable App Sandbox, keep their identifiers and App
  Group, and use public Apple Events APIs. The store edition links no updater. Login
  registration is opt-in, and quitting the app ends its monitoring.
- No external executable runs in either edition. Optional local Rspamd uses a
  fixed-loopback HTTP transport to a separately installed scanner, off by default and
  blocked in local mode. Spamhaus public DNS uses in-process resolver queries.
- Provider mail-sharing permission defaults off, per provider, and is checked before
  credential access and spending reservation and again before each paid request.
  The disclosure covers attachment and OCR text, correction examples and sensitive
  mail. Saving an API key grants no mail-sharing permission. Domain-age lookups need
  a separate opt-in.
- Private Cloud Compute is hidden in both editions; neither holds the managed
  entitlement.
- The privacy manifest declares the data sent to providers and the app's own
  UserDefaults access. The [privacy inventory](privacy-audit.md) records the App
  Privacy answers; do not claim "data not collected" because the user supplies their
  own provider key.
- The app is free, published by Tim Morgan (<tim@tim.codes>). Optional provider usage
  is paid directly to the provider. Offline rules and review work without a provider
  key. A reviewer needs a complete flow using synthetic mail and appropriate access,
  without the owner's personal keys.

## Store release gates

1. Obtain the Mail exception decision.
2. Finish the runtime acceptance work and any store-specific gaps it reveals.
3. Create the App Store Connect app record, then validate a correctly signed store
   package with the original entitlements.
4. Publish the site under `docs/`, enter the privacy answers, screenshots and review
   access, and submit only as a deliberate release step.

The Developer ID edition ships through GitHub Releases with
[GitHubUpdateChecker](https://github.com/RISCfuture/GitHubUpdateChecker), independent
of these gates. Status for each gate is in [TODO.md](../TODO.md); edition differences
are in the [distribution ledger](distribution-differences.md). See also
[App Store packaging](app-store.md) and [lifecycle](lifecycle.md).
