#!/bin/bash
set -euo pipefail
worker="${1:?Pass a token from agent-lock worker}"
mode="${2:-inspect}"
case "$worker" in
  *[!a-zA-Z0-9-]*|'') echo 'Invalid worker token.' >&2; exit 2 ;;
esac
case "$mode" in
  inspect|archive) ;;
  *) echo 'Usage: bash Scripts/app-store-check.sh WORKER [inspect|archive]' >&2; exit 2 ;;
esac
export AGENT_WORKER_ID="$worker"
build_root=".build/$worker/app-store"
mkdir -p "$build_root"
plutil -lint Scripts/AppStoreExportOptions.plist SpamWise/SpamWise.entitlements MailExtension/MailExtension.entitlements
for entitlement in SpamWise/SpamWise.entitlements MailExtension/MailExtension.entitlements; do
  sandbox=$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$entitlement")
  if [[ "$sandbox" != true ]]; then
    echo "App Sandbox missing: $entitlement" >&2
    exit 1
  fi
done
if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.temporary-exception.apple-events' \
  SpamWise/SpamWise.entitlements >/dev/null 2>&1; then
  echo 'Mail Automation uses a temporary exception. App Review justification and approval remain pending.'
fi
if ! /usr/libexec/PlistBuddy -c 'Print :com.apple.developer.private-cloud-compute' \
  SpamWise/SpamWise.entitlements >/dev/null 2>&1; then
  echo 'PCC entitlement is absent. PCC requires an Apple grant and matching distribution profile before use.'
fi
if security find-identity -v -p codesigning | rg 'Apple Distribution:.*\(2NFSK2WB24\)' >/dev/null; then
  echo 'A team Apple Distribution signing identity is installed; profile and installer signing remain separate checks.'
else
  echo 'No team Apple Distribution signing identity found. Signed App Store export is not ready.'
fi
echo 'Export configuration is local-only. This command never uploads or submits an app.'
if [[ "$mode" == inspect ]]; then
  exit 0
fi
xcodebuild -project SpamWise.xcodeproj -scheme SpamWise -destination 'generic/platform=macOS' \
  -derivedDataPath "$build_root/DerivedData" -clonedSourcePackagesDirPath "$build_root/SourcePackages" \
  -archivePath "$build_root/SpamWise.xcarchive" CODE_SIGNING_ALLOWED=NO ENABLE_HARDENED_RUNTIME=YES \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES SWIFT_SUPPRESS_WARNINGS=NO archive \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS=APP_STORE \
  2>&1 | tee "$build_root/archive.log" | xcbeautify
if rg -n 'warning:|error:' "$build_root/archive.log"; then
  exit 1
fi
bash Scripts/check-app-icon.sh "$build_root/SpamWise.xcarchive/Products/Applications/SpamWise.app"
echo 'Unsigned optimized archive passed. Provisioning, App Review and store acceptance remain unverified.'
