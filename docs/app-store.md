# Mac App Store packaging preflight

SpamWise has an App Store export configuration and an isolated local archive
preflight. These are preparation tools. No App Store upload, TestFlight release,
review submission or account-capability change is performed by the preflight.

```sh
bash Scripts/app-store-check.sh <worker-token> inspect
bash Scripts/app-store-check.sh <worker-token> archive
```

Obtain a distinct token with `agent-lock worker`. Archive mode places its unsigned,
optimized app and extension in `.build/<worker-token>/app-store/SpamWise.xcarchive`.
It builds with warnings treated as errors and checks the sandbox entitlements.
An unsigned archive verifies compilation and bundle assembly; it does not verify
store signing, entitlements granted by a profile or App Review acceptance.

## Signing and local export

The original bundle identifiers, team `2NFSK2WB24`, App Group
`group.codes.tim.SpamWise` and shared Keychain group must remain intact. Apple's
[distribution-signing guidance](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/)
requires the distribution identity and matching profiles for the app and nested
extension. Apple Distribution and 3rd Party Mac Developer Installer identities
for this team were present on 2026-10-16.

A signed archive intended for the store needs existing App Store distribution
profiles for both bundle IDs and authorized capabilities. Xcode account access or
managed signing credentials may be required to create/download those profiles.
See Apple's [App Store profile instructions](https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile).
Do not grant or fabricate a managed entitlement merely to make signing succeed.

After creating a signed archive with the app and extension entitlements intact,
this command attempts a local export using existing signing material:

```sh
xcodebuild -exportArchive \
  -archivePath /absolute/path/to/signed/SpamWise.xcarchive \
  -exportPath /absolute/path/to/local/app-store-export \
  -exportOptionsPlist Scripts/AppStoreExportOptions.plist
```

A development-signed archive can be created with existing local profiles, preserving
the source entitlements, before App Store export re-signs it for distribution:

```sh
export AGENT_WORKER_ID=<worker-token>
xcodebuild -project SpamWise.xcodeproj -scheme SpamWise \
  -destination 'generic/platform=macOS' \
  -derivedDataPath .build/$AGENT_WORKER_ID/app-store/DerivedData \
  -clonedSourcePackagesDirPath .build/$AGENT_WORKER_ID/app-store/SourcePackages \
  -archivePath .build/$AGENT_WORKER_ID/app-store/SpamWise-signed.xcarchive \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=2NFSK2WB24 \
  CODE_SIGN_IDENTITY='Apple Development' ENABLE_HARDENED_RUNTIME=YES \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES SWIFT_SUPPRESS_WARNINGS=NO archive
```

The plist sets `method=app-store-connect` and `destination=export`; it never selects
upload. It preserves the version/build number and disables symbol upload. No
`-allowProvisioningUpdates` flag is added, so account changes are not requested.
Missing profiles or credentials should fail the export. The preflight's unsigned
archive is not a distribution-ready signed archive.

Do not export the unsigned preflight archive as a release candidate: Xcode can
generate empty extension entitlements when no original code signature records
them. Build a separate signed archive and compare both exported entitlement sets
with the source before accepting the package.

The 2026-10-16 inventory decoded 73 installed profiles. SpamWise and its extension
had device-bound Mac Team profiles and Developer ID profiles, but no Mac App Store
profiles. The existing Match repository contained 26 profile files and no SpamWise
profile. The initial local export failed with `No profiles for 'codes.tim.SpamWise'
were found`, explicitly identifying the missing Mac App Store provisioning profile.
The log is `.build/7065c63f-e440-403b-882a-0686bdde7442/app-store/export.log`.

A subsequent authorized provisioning attempt reached distribution signing. The
proper development-signed archive passed its warning-free optimized build and
deep strict signature verification, with the original app and extension
entitlements present. Its App Store export requested Keychain approval for the
Apple Distribution private key at 09:57:40 PDT on 2026-10-16. At that observation,
signing was waiting for the user's Keychain approval and no store package had been
produced. The archive is
`.build/7065c63f-e440-403b-882a-0686bdde7442/app-store/SpamWise-signed.xcarchive`;
the export log is in the same directory as `export-signed.log`.

At 10:03 PDT the export parent had exited without a package while its signing child
still awaited approval. The abandoned signing child was terminated. The signed
archive remains available; no upload or release occurred. A local export must be
run again when Keychain access is available. Use a fresh archive for subsequent
source changes.

For authorized signing preparation, add `-allowProvisioningUpdates` to the local
export command to let the configured Xcode account create or download matching
profiles for the existing identifiers and capabilities. This still uses
`destination=export`; it does not upload or release the app. Do not remove
entitlements to force an export or request a managed PCC grant through this step.

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
mail. App Review approval remains pending. The explicit IMAP route provides an
independent account connection; switching routes in preferences does not remove
the compiled app's temporary-exception entitlement. A separate store-specific
entitlement or feature change would require its own implementation and validation.

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

App Store Connect metadata, privacy disclosures for mail sent to selected external
providers, required entitlement justification, distribution profiles, local signed
export, store validation and review remain separate work. The headless CLI is a
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
| Subtitle | Mail filtering you control |
| Primary category | Productivity |
| Keywords | email,junk,inbox,filter,privacy,imap,review,rules |
| Promotional text | Preview mail decisions, set your own sender rules, and review uncertain messages before enabling automatic actions. |

Description draft:

> SpamWise helps you sort unwanted mail while keeping you in control. Start in dry
> run to inspect decisions and explanations. Address and domain rules take priority,
> and corrections update the rules you choose. Review uncertain messages, inspect
> estimated model usage, and pause processing whenever you need to.
>
> Connect through Apple Mail or configure a separate TLS IMAP account. Automatic
> moves require account validation. SpamWise never deletes mail or moves it to
> Trash. Choose an available on-device model or configure a supported external
> provider with your own API credentials. External providers receive bounded mail
> context and may charge for requests; dry run can still make model requests.

Do not advertise PCC availability until its grant and signed runtime are verified.
Screenshots must come from the reviewed release build and must use synthetic mail.
The publisher still needs to supply the public support URL, privacy-policy URL,
copyright, pricing and territory decisions, and final age-rating answers.

## Privacy-policy and disclosure draft

Policy draft for review before publication:

> SpamWise processes mail from accounts you explicitly connect. It stores settings,
> sender rules, decision records, corrections, and bounded retry data locally.
> Optional learning and reviewed-content settings retain additional local data.
> API credentials and app-configured IMAP credentials are stored in Keychain.
>
> When you choose Anthropic Claude, OpenAI, or Google Gemini, SpamWise sends bounded
> message text, subject, evidence, preferences, and selected correction examples to
> that provider using your credentials. Mail context can contain personal or
> sensitive information. Your provider's terms and retention settings apply.
> Selecting an on-device model performs model inference on your Mac. Optional
> domain reputation checks send queried domains to the configured DNS service;
> domain-age lookups contact registration-data services. An optional local Rspamd
> integration passes mail to your separately configured scanner, whose own network
> behavior and retention are controlled by its configuration.
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
