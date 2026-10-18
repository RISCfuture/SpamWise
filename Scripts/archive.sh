#!/bin/bash
set -euo pipefail
worker="${1:?Pass a token from agent-lock worker}"
mode="${2:-signed}"
export AGENT_WORKER_ID="$worker"
build_root=".build/$worker"
archive="$build_root/SpamWise.xcarchive"
mkdir -p "$build_root"
signing=(-allowProvisioningUpdates CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=2NFSK2WB24)
if [[ "$mode" == unsigned ]]; then
  signing=(CODE_SIGNING_ALLOWED=NO)
elif [[ "$mode" != signed ]]; then
  echo 'Usage: bash Scripts/archive.sh WORKER signed|unsigned [NOTARY_KEYCHAIN_PROFILE]' >&2
  exit 2
fi
bash Scripts/help-index.sh
xcodebuild -project SpamWise.xcodeproj -scheme SpamWise -destination 'generic/platform=macOS' \
  -derivedDataPath "$build_root/DerivedData" -clonedSourcePackagesDirPath "$build_root/SourcePackages" \
  -archivePath "$archive" ENABLE_HARDENED_RUNTIME=YES SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
  SWIFT_SUPPRESS_WARNINGS=NO "${signing[@]}" archive 2>&1 | tee "$build_root/archive.log" | xcbeautify
if rg -n 'warning:|error:' "$build_root/archive.log"; then exit 1; fi
bash Scripts/check-app-icon.sh "$archive/Products/Applications/SpamWise.app"
if [[ "$mode" == unsigned ]]; then exit 0; fi
cat > "$build_root/ExportOptions.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>developer-id</string>
<key>signingStyle</key><string>automatic</string>
<key>teamID</key><string>2NFSK2WB24</string>
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath "$archive" -exportPath "$build_root/export" \
  -exportOptionsPlist "$build_root/ExportOptions.plist" -allowProvisioningUpdates \
  2>&1 | tee "$build_root/export.log" | xcbeautify
app="$build_root/export/SpamWise.app"
bash Scripts/check-app-icon.sh "$app"
codesign --verify --deep --strict --verbose=2 "$app"
codesign --display --verbose=4 "$app"
if [[ -n "${3:-}" ]]; then
  ditto -c -k --keepParent "$app" "$build_root/SpamWise.zip"
  xcrun notarytool submit "$build_root/SpamWise.zip" --keychain-profile "$3" --wait
  xcrun stapler staple "$app"
  spctl --assess --type execute --verbose=2 "$app"
fi
