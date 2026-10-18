# Direct release updates

The download edition (`SpamWise-download` target, `SpamWise (download)` scheme)
checks GitHub for new releases with
[GitHubUpdateChecker](https://github.com/RISCfuture/GitHubUpdateChecker), pinned
to the 2.x series from version 2.3.0 in the project's `Package.resolved`. The
App Store edition does not link the library; the store keeps it current.

Dependency pins live in the project's
`SpamWise.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` and
in `SpamWiseCore/Package.resolved`, alongside the pinned Claude revision in the core
manifest. Both lock files are committed. Reproduce release builds with
`-onlyUsePackageVersionsFromResolvedFile` so resolution uses exactly those pins.
To develop the library alongside the app, drag a local checkout into the Xcode
project as a package override; never commit a path reference.

## Configuration

`Config/SpamWise.xcconfig` sets `SPAMWISE_UPDATE_OWNER` (`RISCfuture`) and
`SPAMWISE_UPDATE_REPOSITORY` (`SpamWise`). The download edition's Info.plist
carries them as `SpamWiseUpdateOwner` and `SpamWiseUpdateRepository`, and
`DirectUpdateConfiguration` reads them back at launch. A bundle with missing or
malformed values, a different bundle identifier, or a Mac App Store receipt
gets no checker, and the update command and settings stay hidden. There is no
runtime override, and release responses cannot change the repository.

The release lanes refuse to package a download build whose values are missing
or malformed: `ci_verify_release_notes` checks the xcconfig before anything is
built, and `download_release` checks the exported app's Info.plist before
notarizing it.

## Behavior

At launch the download edition starts the library's scheduled checks; the
cadence (hourly, daily, weekly or never) and prerelease preference are in
Settings → General → App updates, beside Check Now and Reset Skipped Versions.
The app menu adds Check for Updates…. Checks compare the release tag with
`CFBundleShortVersionString`, so tags carry no `v` prefix. They send GitHub the
normal network request information and no mail content or credentials.

SpamWise is sandboxed, and the library never installs automatically into a
sandboxed app: it downloads the release's disk image and hands the user the
file to install. Releases ship one asset, the notarized and stapled disk image
`.github/workflows/release.yml` attaches.

Install one edition at a time: both share the bundle identifier, App Group and
Mail extension. Release and edition-switching acceptance is tracked under SS-20 in
[TODO.md](../TODO.md).
