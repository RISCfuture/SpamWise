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

### Validation gate

Authenticated `altool --validate-app` stops with error 19 until an App Store Connect
app record exists for bundle ID `codes.tim.SpamWise` on platform macOS. Apple's
[Apps API documentation](https://developer.apple.com/documentation/appstoreconnectapi/apps)
directs developers to create new apps on the App Store Connect website; the API key
does not provide that creation operation.

### Export compliance

Both editions set `ITSAppUsesNonExemptEncryption` to `NO`, so App Store Connect
asks no encryption question on upload: SpamWise uses only the encryption macOS
provides, TLS through URLSession and Network.framework and AES-GCM through CryptoKit.

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

Every action path, from history import and lookup to Junk and Inbox moves, flags,
read status and clearing Mail's junk mark, goes through this exception, and the Mail
extension alone does nothing. A store build without it could not filter mail, so the exception decision gates the
whole edition; see [feasibility](app-store-feasibility.md). The
[review notes](app-review-notes.md) draft the justification: bounded,
account-specific Mail actions, user consent, dry-run defaults, persist-before-action
and refusal to delete mail. IMAP does not remove the need for the entitlement in the
current build.

## Private Cloud Compute

Neither edition requests `com.apple.developer.private-cloud-compute`, so neither
offers PCC, and a restored PCC selection fails open with a prompt to choose another
model. Apple's [PCC eligibility page](https://developer.apple.com/private-cloud-compute/)
requires Small Business Program membership, fewer than two million first-time
App Store downloads, and the entitlement assigned to the developer account.
Eligible distribution is through the App Store; Apple lists TestFlight and ad hoc
for testing. Developer ID notarization alone does not satisfy those conditions.

Confirm the account grant and matching app/profile capability before introducing
the entitlement and showing the choice again.

## Privacy answers

The policy is [privacy.md](privacy.md), published as the site's privacy page. The App
Privacy answers, the manifest's collected-data types and the source inventory are all
in [the privacy inventory](privacy-audit.md); enter the answers from there rather than
from Xcode's privacy report alone, which cannot see what providers receive. Open
submission steps are tracked in [TODO.md](../TODO.md).

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
| Primary category | Utilities |
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

Do not advertise PCC; neither edition offers it.
Screenshots must come from the reviewed release build and must use synthetic mail.
Publish privacy and support pages with the marketing site under `docs/`, hosted
through GitHub Pages. Publisher/contact and free pricing are confirmed. Use copyright
Tim Morgan for the release year. Do not invent a deployed URL before the site is
published.
