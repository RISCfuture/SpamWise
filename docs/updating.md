# Direct release updates

The `SpamWiseDirect` target integrates the `GitHubReleaseDiscovery` product of
[GitHubUpdateChecker](https://github.com/RISCfuture/GitHubUpdateChecker) for **manual release discovery**. Settings → General → App updates checks the configured public GitHub
repository only after a click. It accepts stable releases, compares the installed
marketing version, and offers a GitHub releases-page link. There are no startup
checks, downloads, binary replacement, automatic relaunches or channel switches.

`RISCfuture/SpamWise` is the selected release repository, created privately pending
publication approval. The direct-target build settings remain unconfigured until
a public release channel is approved. An unconfigured build shows an unavailable
status and constructs no checker. Missing
or malformed configuration fails closed; an existing Mac App Store receipt also
disables direct checks. This receipt-presence guard is not receipt authentication.

## Explicit configuration

The shared `SpamWiseDirect` scheme builds a sandboxed app with the existing bundle
identifier `codes.tim.SpamWise`, team `2NFSK2WB24`, App Group and extension. Only
this target links GitHubReleaseDiscovery, resolved as a remote package from version
2.3.0 up to the next major version. To develop the library alongside the app, drag
a local checkout into the Xcode project as a package override; never commit a path
reference.

Once the actual public release repository exists, set these direct-target build
settings to its confirmed values:

- `SPAMWISE_UPDATE_OWNER`: `RISCfuture`.
- `SPAMWISE_UPDATE_REPOSITORY`: `SpamWise`.

They populate `SpamWiseUpdateOwner` and `SpamWiseUpdateRepository` in the signed
app plist. `SpamWiseDistribution` is `direct`. The defaults are empty. There is
no user preference or environment override at runtime; release responses cannot
change the configured repository. The browser link is constructed from the
validated configuration, not from a URL supplied in the release response.

Use semantic version tags and increment `MARKETING_VERSION` for a discoverable
release. Do not silently replace an artifact under an existing version tag.
Prerelease and draft releases are not offered. GitHub API failures produce a
retryable status without affecting mail processing. Checks disclose the normal
network request information to GitHub; no mail content or provider credentials
are included.

For an isolated build, obtain a token using `agent-lock worker`, set
`AGENT_WORKER_ID` to it, and run:

```sh
xcodebuild -project SpamWise.xcodeproj -scheme SpamWiseDirect \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/$AGENT_WORKER_ID/direct/DerivedData \
  -clonedSourcePackagesDirPath .build/$AGENT_WORKER_ID/direct/SourcePackages \
  CODE_SIGNING_ALLOWED=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
  SWIFT_SUPPRESS_WARNINGS=NO build
```

This builds the unconfigured variant and makes no release checks. Supply the two
build settings only after a host has been confirmed. No release is uploaded by
this command.

## Library dependency

The library exposes its existing API client, semantic version parser and release
models as a separate Foundation/Logging product. SpamWise does not link the
library's updater UI, downloader, installer or MarkdownUI dependency. The original
`GitHubUpdateChecker` product retains its public API through typealiases to the
shared discovery types. The product first shipped in GitHubUpdateChecker 2.3.0.

Dependency pins live in the project's
`SpamWise.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` and
in `SpamWiseCore/Package.resolved`, alongside the pinned Claude revision in the core
manifest.
During verification, Xcode repeatedly removed the project-workspace lock file
for these local package references, including after successful resolution with
`-onlyUsePackageVersionsFromResolvedFile`. That generated workspace file is not
maintained separately. Preserve both package-owned lock files and the reviewed
library checkout when reproducing release builds.

This separation also avoids the original MarkdownUI dependency's Swift 6.4
`@_implementationOnly` warnings in SpamWise's direct build. Those upstream UI
warnings remain outside the discovery product; no warning suppression is enabled.

## Why installation remains manual

The inspected local library's `AppInstaller.supportsAutoInstall` rejects sandboxed
apps. Its installation implementation replaces the existing bundle before
checking only bundle structure, and removes quarantine. It does not establish a
trusted signing requirement, matching team/bundle identity, notarization,
distribution channel or rollback safety. SpamWise never calls that installer,
the library's download methods, its automatic scheduler, or its built-in update
UI, which can lead to installation. Signature verification is not claimed for
the release-page link.

SS-20 therefore remains incomplete. Before enabling automatic installation, the
library/integration needs an audited path that verifies the candidate **before**
replacement: intact signature, expected Developer ID team and app/extension
identities, intended direct channel, notarization and version. It must retain
quarantine protections, preserve the working app on failure, handle interruption
and rollback, and work within the approved sandbox/distribution design. Do not
disable the sandbox or weaken signing to make updates work.

## Acceptance still required

- Publish the approved `RISCfuture/SpamWise` release channel and pin a reviewed library revision for
  reproducible release builds; the current dependency is a local checkout.
- Publish an authorized signed/notarized direct artifact and verify discovery,
  offline errors, no releases, rate limiting, prereleases and version ordering.
- Verify the browser handoff and manual replacement with disposable installs.
  Do not treat a release page as proof of binary authenticity.
- Inspect the final `APP_STORE` archive: its dependency graph, binary symbols and
  bundled resources must exclude GitHubReleaseDiscovery, GitHubUpdateChecker and its updater UI. The
  existing `SpamWise` target has no updater dependency; the direct target rejects
  `APP_STORE` at compile time.
- Validate channel replacement, settings migration, Mail extension registration,
  login-item registration, spend limits and replay protection. The shared bundle
  identity supports one installation at a time; migration acceptance is pending.
- Run the signed UI and update recovery acceptance before presenting automatic
  updating as supported. No release feed, download or installation was contacted
  by implementing these changes.

## Local verification — 2026-10-16

Using isolated worker `0c37f7f0-ed0f-488a-88ea-e4c37df60098`:

- `SpamWiseDirect` and a fresh `SpamWise` build with `APP_STORE` both compile with
  warnings treated as errors and zero warning/error diagnostics. Builds are
  unsigned; distribution signing and App Review are not established by them.
- Binary-symbol/resource inspection finds discovery code only in the direct app,
  no installer or MarkdownUI code in either app, and no discovery/updater resource
  bundle in the store app. Store dependency graph contains no updater target.
- The built direct plist contains `SpamWiseDistribution=direct` and empty
  owner/repository values. The unconfigured build cannot initiate release checks.
- Four configuration tests pass, including 17 malformed/unconfigured owner/repo
  cases, repository-derived link construction, and rejection of wrong channel,
  bundle identity and receipt-bearing bundles. These run the production
  configuration source with Swift Testing in an isolated executable, without
  launching the production app.
- The library's 30 existing tests pass: 19 discovery and 11 original-product
  tests. This is a default `swift test` run, not a claim that the original UI
  product's upstream MarkdownUI builds warning-free with warnings-as-errors.
- Simultaneous `APP_STORE` and `SPAMWISE_DIRECT_UPDATES` flags produce the intended
  compiler error. Swift formatting, strict SwiftLint on the changed files, plist
  validation and Markdown lint pass. The library's existing lint configuration
  emits two configuration warnings about disabled/renamed rules.

Logs are `.build/direct-updates-build.log`,
`.build/direct-updates-mas-build.log`, `.build/direct-updates-config-tests.log`,
`.build/direct-updates-library-tests.log` and
`.build/direct-updates-channel-guard.log`. No network release request, download,
installation, signed update UI or migration acceptance ran.
