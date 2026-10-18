# Help, signing, and packaging

## Editions

SpamWise ships two editions from one project. Both share the bundle identifier
`codes.tim.SpamWise`, the Mail extension, the App Group, the shared Keychain
group and every line of the interface, which lives in the `SpamWise Common`
framework.

| Edition | Scheme | Distribution | Updates |
| --- | --- | --- | --- |
| Mac App Store | `SpamWise (MAS)` | App Store Connect | The store |
| Download | `SpamWise (download)` | Notarized disk image on GitHub | GitHubUpdateChecker |

Each edition has its own `App` struct, Info.plist and entitlements under
`SpamWise-MAS/` and `SpamWise-download/`. The download edition reads its update
repository from `SPAMWISE_UPDATE_OWNER` and `SPAMWISE_UPDATE_REPOSITORY` in
`Config/SpamWise.xcconfig`. Install one edition at a time: both register the
same extension and share one store.

## Help book

`SpamWise/SpamWise.help` contains six pages per language and a Core Spotlight
Help index. Each edition's Info.plist registers the book with
`CFBundleHelpBookFolder` and `CFBundleHelpBookName`. Rebuild the index after
editing HTML:

```sh
Scripts/help-index.sh
```

The release lanes run it before every archive.

## Versions

`Config/SpamWise.xcconfig` holds the version a development build carries. A
release stamps `MARKETING_VERSION` from the tag and `CURRENT_PROJECT_VERSION`
from the commit count on the command line, so a release leaves no commit
behind. Each release needs a `## <version>` section in `CHANGELOG.md`;
`Scripts/release-notes.sh` renders it for the GitHub release and App Store
Connect.

## Release lanes

Signing goes through fastlane match against the shared certificates
repository. Install the bundle into the project's RVM gemset, then copy
`fastlane/.env.example` to `fastlane/.env` and set `MATCH_PASSWORD`.

```sh
bundle install
bundle exec fastlane lanes
bundle exec fastlane mac download_release version:1.0 build:42
bundle exec fastlane mac release version:1.0 build:42
```

`download_release` archives the download edition, exports it for Developer
ID, refuses an app whose update repository is missing or malformed, notarizes
and staples the app, builds `build/SpamWise-<version>.dmg` from the stapled
app, then signs, notarizes and staples the disk image. `release` uploads the
App Store edition to App Store Connect without submitting it for review.
Both keep the archive's dSYMs as `build/SpamWise-<version>.dSYM.zip`.

Pushing a version tag runs the same lanes in `.github/workflows/release.yml`.
It first checks the changelog section and the update repository, then
archives both editions, attaches the notarized disk image to a GitHub release
and attaches the App Store build to its version.

## App icon and signatures

`Scripts/check-app-icon.sh` fails unless a bundle contains `Contents/Resources/Assets.car` and its `Info.plist` sets `CFBundleIconName` to `AppIcon`. `check.sh` runs it on each edition's Debug app, and the release lanes run it on every archived app. The icon source is the Icon Composer bundle `SpamWise/AppIcon.icon`, which both app targets compile through `ASSETCATALOG_COMPILER_APPICON_NAME`.

The app and extension preserve their original identifiers and share `group.codes.tim.SpamWise` plus the Keychain group `2NFSK2WB24.codes.tim.SpamWise.shared`. The app retains Automation and Contacts entitlements. Inspect both nested extension and app signatures before distribution. Never distribute an unsigned or unnotarized download build as a completed release.

## Release checklist

Confirm each item on the exported bundle you will distribute:

- `bash Scripts/check-app-icon.sh build/SpamWise.app` passes: `Assets.car` is present and `CFBundleIconName` is `AppIcon`.
- `codesign --verify --deep --strict` passes for the app and its nested extension.
- Notarization is accepted, the ticket is stapled, and `spctl --assess --type execute` reports a notarized Developer ID.

## Acceptance on a fresh setup

Use a fresh local app state and controlled test mail. Record elapsed onboarding time (target under five minutes), API/model availability, actual incoming body callbacks, account identity, shared Keychain and App Group access, Automation/Contacts denied states, Review annotations, account-specific Inbox/Junk moves, pause/dry-run behavior, corrections, and fail-open behavior for network, parsing, storage, and timeout failures. Repeat across configured accounts and server-routed Junk. Establish a callback deadline with controlled delays; the current deadline is provisional.

Use the complete [runtime probe checklist](probes/runtime-checklist.md). UI automation and signed integration are separate checks. Build success, synthetic fixture outcomes, and generated AppleScript compilation do not substitute for either.
