#!/bin/bash
#
# Runs the XCTest UI flows against a development-signed App Store edition.
#
#   Scripts/ui-check.sh [build-token]
#
# Signing is automatic for team 2NFSK2WB24: the UITests runner needs an embedded provisioning
# profile, which Xcode downloads or creates with the configured team account. The test-mode app
# uses isolated temporary storage and a simulated denied Mail permission, so no mail is touched.
#
# Products land in .build/<build-token>/ (.build/check/ by default), beside Scripts/check.sh's.

set -euo pipefail
cd "$(dirname "$0")/.."

token="${1:-check}"
case "$token" in
  *[!a-zA-Z0-9-]*) echo "Build tokens may contain only letters, digits and hyphens." >&2; exit 2 ;;
esac
build_root=".build/$token"
mkdir -p "$build_root"

xcodebuild -project SpamWise.xcodeproj -scheme "SpamWise (MAS)" \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$build_root/DerivedData" \
  -clonedSourcePackagesDirPath "$build_root/SourcePackages" \
  -allowProvisioningUpdates CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM=2NFSK2WB24 CODE_SIGN_IDENTITY="Apple Development" \
  -only-testing:UITests test 2>&1 | tee "$build_root/ui.log" | xcbeautify
