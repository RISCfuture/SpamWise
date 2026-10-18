# Mac App Store packaging

The App Store edition is the `SpamWise-MAS` target, built by the shared
`SpamWise (MAS)` scheme with Release as its archive configuration. It links no
updater, and nothing about the edition depends on a compilation flag passed on
the command line, so an Xcode Organizer archive and a release lane produce the
same app.

```sh
bundle exec fastlane mac release version:1.0 build:42
```

The `release` lane installs the App Store and Mac Installer Distribution
certificates and both bundles' App Store profiles through fastlane match,
archives the scheme, exports it for App Store Connect and uploads the package
without submitting it for review. `beta` uploads the same build to TestFlight.
Tagging a version runs the lane in `.github/workflows/release.yml`, which then
writes the version's notes from `CHANGELOG.md` and attaches the build once
Apple has processed it. See [packaging](packaging.md).

## Signing

The original bundle identifiers, team `2NFSK2WB24`, App Group
`group.codes.tim.SpamWise` and shared Keychain group must remain intact. Apple's
[distribution-signing guidance](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/)
requires the distribution identity and matching profiles for the app and nested
extension; `fastlane/Matchfile` lists both identifiers so match syncs a profile
for each. Do not grant or fabricate a managed entitlement merely to make
signing succeed.

### Current validation gate

On October 16, 2026, an `altool --validate-app` attempt with the shared App
Store Connect API key stopped with error 19: no Apple ID was found for bundle
ID `codes.tim.SpamWise` on platform `macOS App`. An App Store Connect app record
must exist before an upload can succeed. Apple's
[Apps API documentation](https://developer.apple.com/documentation/appstoreconnectapi/apps)
directs developers to create new apps on the App Store Connect website; the API
key does not provide that creation operation. Server validation, final metadata
and App Review remain open.

## Mail Automation exception

The app currently declares
`com.apple.security.temporary-exception.apple-events` for `com.apple.mail` in
addition to its Automation entitlement. Apple instructs developers to identify
requested exceptions and explain their necessity in App Store Connect; this is
an App Review decision, not an automatic rejection implied by the presence of
the key. Apple's [temporary-exception documentation](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/AppSandboxTemporaryExceptionEntitlements.html)
prefers scripting-target access groups when the target exposes a suitable group.
Mail composition permission does not establish access to SpamWise's existing-mail
inspection and move operations.

Prepare an accurate justification for the bounded, account-specific Mail actions,
user consent, dry-run defaults, persist-before-action policy and refusal to delete
mail. App Review approval remains pending. Mail.app is the supported product focus;
the existing experimental IMAP code does not establish a store workaround or remove
the compiled app's temporary-exception entitlement.

## Private Cloud Compute

The current app does not request `com.apple.developer.private-cloud-compute`.
Selecting PCC therefore cannot be claimed as a working distribution feature.
Apple's [PCC eligibility page](https://developer.apple.com/private-cloud-compute/)
requires Small Business Program membership, fewer than two million first-time
App Store downloads, and the entitlement assigned to the developer account.
Eligible distribution is through the App Store; Apple lists TestFlight and ad hoc
for testing. Developer ID notarization alone does not satisfy those conditions.

Confirm the account grant and matching app/profile capability before introducing
the entitlement or claiming PCC acceptance. The missing grant blocks PCC use;
it does not by itself establish rejection of an app that uses another explicit
provider and fails open when PCC is unavailable.

## Remaining acceptance

The local signed package and compatible distribution profiles are verified.
App Store Connect app creation, final metadata/privacy answers, published policy
and support URLs, the Mail exception issue reference, server validation and review
remain open. Drafts are in [review notes](app-review-notes.md) and the
[privacy audit](privacy-audit.md); the static site is prepared under `docs/`. The headless CLI is a
standalone package executable and is not installed as an automatic background
service by the app or this script. No production account or mailbox is contacted
by packaging checks.

## Product-page draft

These drafts describe implemented behavior; publishing them remains separate work.
Apple documents the [app information fields](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/)
and [version metadata](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information).

| Field | Draft |
| --- | --- |
| Name | SpamWise |
| Publisher | Tim Morgan |
| Contact | <tim@tim.codes> |
| Price | Free; optional third-party API usage is billed separately by the provider |
| Subtitle | Mail filtering you control |
| Primary category | Productivity |
| Keywords | email,junk,inbox,filter,privacy,mail,review,rules |
| Promotional text | Preview mail decisions, set your own sender rules, and review uncertain messages before enabling automatic actions. |

Description draft:

> SpamWise helps you sort unwanted mail while keeping you in control. Start in dry
> run to inspect decisions and explanations. Address and domain rules take priority,
> and corrections update the rules you choose. Review uncertain messages, inspect
> estimated model usage, and pause processing whenever you need to.
>
> Connect through Apple Mail. Automatic
> moves require account validation. SpamWise never deletes mail or moves it to
> Trash. Choose an available on-device model or configure a supported external
> provider with your own API credentials. External providers receive bounded mail
> context and may charge for requests; dry run can still make model requests.

Do not advertise PCC availability until its grant and signed runtime are verified.
Screenshots must come from the reviewed release build and must use synthetic mail.
Publish privacy and support pages with the marketing site under `docs/`, hosted
through GitHub Pages. Publisher/contact and free pricing are confirmed; the public
site address, territory choices and final age-rating answers remain release work.
Use copyright Tim Morgan for the release year. Do not invent a deployed URL before
the hosting repository and address exist.

## Privacy-policy and disclosure draft

Policy draft for review before publication:

> SpamWise processes mail from accounts you explicitly connect. It stores settings,
> sender rules, decision records, corrections, and bounded retry data locally.
> Optional learning and reviewed-content settings retain additional local data.
> API credentials and app-configured IMAP credentials are stored in Keychain.
>
> When you grant mail-sharing permission to Anthropic Claude, OpenAI, or Google Gemini, SpamWise sends bounded
> message text, subject, evidence, preferences, and selected correction examples to
> that provider using your credentials. Mail context can contain personal or
> sensitive information. Your provider's terms and retention settings apply.
> Selecting an on-device model performs model inference on your Mac. Optional
> domain reputation checks send queried domains to the configured DNS service;
> optional domain-age lookups contact registration-data services. You can revoke
> provider permission in Account settings; already dispatched requests cannot be
> recalled. The App Store build excludes external executable scanners.
>
> Contacts permission, when granted, supplies local trusted-sender evidence.
> SpamWise has no advertising or tracking integration. Pausing stops new processing;
> dry run suppresses mail actions but does not suppress provider requests.

The [App Privacy questionnaire](https://developer.apple.com/app-store/app-privacy-details/)
includes third-party practices. Its collection definition depends on access beyond
servicing the request in real time; ordinary optional processing does not
automatically qualify for an exemption. Review provider retention and account
settings before submitting answers. The following is a draft inventory, not a
submitted privacy label:

| Data | Current use and disclosure review |
| --- | --- |
| Emails or Text Messages | Selected remote models receive bounded mail context for app functionality; treat as potentially linked, not anonymized. |
| Other User Content | Preferences and correction examples may reach the selected provider for app functionality. |
| Identifiers | Provider authentication and IMAP account identifiers can link requests to the user's service account. |
| Contacts | Address matching is local; confirm no address-book list is transmitted by the release build. |
| Diagnostics and usage | Local activity, estimated costs and retry state are not themselves analytics collection; assess any downstream provider logs separately. |

The publisher must confirm provider-specific retention, linkage and data categories,
publish the final policy with a real contact address, and verify the release's
required-reason API/privacy-manifest requirements. No blanket “data not collected”
claim follows from local storage or user-supplied API keys.
