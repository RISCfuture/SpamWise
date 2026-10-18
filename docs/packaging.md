# Help, signing, and packaging

## Help book

`SpamWise/SpamWise.help` contains six English pages and a Core Spotlight Help index. `CFBundleHelpBookFolder` and `CFBundleHelpBookName` register the book; the Help menu and contextual controls open named anchors. Rebuild the index after editing HTML:

```sh
bash Scripts/help-index.sh
```

The index uses `hiutil -I corespotlight -C -a -s en`. The app build must include the whole `.help` folder with its `Contents` structure intact. This is a local Help book with no remote assets.

## Archive and Developer ID export

```sh
bash Scripts/archive.sh <worker-token> unsigned
bash Scripts/archive.sh <worker-token> signed
```

Unsigned mode validates an optimized hardened-runtime archive. Signed mode uses automatic development provisioning for the archive, then exports with the `developer-id` method and team `2NFSK2WB24`. Xcode may need account access to create or download profiles. A valid certificate alone does not prove that required App Group and Keychain entitlements are authorized. The script fails if compilation, provisioning, export, or signature verification fails.

`check.sh` runs `Scripts/check-app-icon.sh` on the Debug app. Both `archive.sh` and `app-store-check.sh archive` run it on the archived app, `archive.sh` runs it again on the exported app, and `export-store-match.py` runs it on the re-signed app before building the installer package. It fails unless the bundle contains `Contents/Resources/Assets.car` and its `Info.plist` sets `CFBundleIconName` to `AppIcon`. The icon source is the Icon Composer bundle `SpamWise/AppIcon.icon`, shared by the SpamWise and SpamWiseDirect targets through `ASSETCATALOG_COMPILER_APPICON_NAME`.

Artifacts are under `.build/<worker-token>/`: `SpamWise.xcarchive`, `export/SpamWise.app`, and command logs. The app and extension preserve their original identifiers and share `group.codes.tim.SpamWise` plus the Keychain group `2NFSK2WB24.codes.tim.SpamWise.shared`. The app retains Automation and Contacts entitlements. Inspect both nested extension and app signatures before distribution.

## Notarization

Pass an existing `notarytool` Keychain profile as the third argument:

```sh
bash Scripts/archive.sh <worker-token> signed <notary-keychain-profile>
```

This uploads the Developer ID archive to Apple, waits for acceptance, staples the ticket, and checks Gatekeeper assessment. Credentials remain in Keychain. Without a profile, the script stops after Developer ID export and does not claim notarization. Never distribute an unsigned or unnotarized build as a completed release.

## Release checklist

Confirm each item on the exported bundle you will distribute:

- `bash Scripts/check-app-icon.sh .build/<worker-token>/export/SpamWise.app` passes: `Assets.car` is present and `CFBundleIconName` is `AppIcon`.
- `codesign --verify --deep --strict` passes for the app and its nested extension.
- Notarization is accepted, the ticket is stapled, and `spctl --assess --type execute` reports a notarized Developer ID.

## Acceptance on a fresh setup

Use a fresh local app state and controlled test mail. Record elapsed onboarding time (target under five minutes), API/model availability, actual incoming body callbacks, account identity, shared Keychain and App Group access, Automation/Contacts denied states, Review annotations, account-specific Inbox/Junk moves, pause/dry-run behavior, corrections, and fail-open behavior for network, parsing, storage, and timeout failures. Repeat across configured accounts and server-routed Junk. Establish a callback deadline with controlled delays; the current deadline is provisional.

Use the complete [runtime probe checklist](probes/runtime-checklist.md). UI automation and signed integration are separate checks. Build success, synthetic fixture outcomes, and generated AppleScript compilation do not substitute for either.

## Match API key alternative

If no notarytool Keychain profile exists, use the encrypted API key in the Match repository and an existing project's environment file containing the shared `MATCH_PASSWORD`:

```sh
python3 Scripts/notarize-match.py --certificates ~/Repositories/certificates \
  --env-file /path/to/project/fastlane/.env
```

Without `--archive`, this authenticates with Apple's notarization history endpoint. The helper reads only the literal `MATCH_PASSWORD` assignment, captures decrypted JSON in memory, writes the required `.p8` to a private temporary directory with mode 600, and removes it after the command. It never prints the password or key and does not modify the Match repository or certificates.

After Developer ID export, zip the final app and submit:

```sh
ditto -c -k --keepParent .build/<worker-token>/export/SpamWise.app .build/<worker-token>/SpamWise.zip
python3 Scripts/notarize-match.py --certificates ~/Repositories/certificates \
  --env-file /path/to/project/fastlane/.env --archive .build/<worker-token>/SpamWise.zip \
  --output .build/<worker-token>/notarization.json
xcrun stapler staple .build/<worker-token>/export/SpamWise.app
spctl --assess --type execute --verbose=2 .build/<worker-token>/export/SpamWise.app
```
