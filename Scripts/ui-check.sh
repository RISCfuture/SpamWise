#!/bin/bash
set -euo pipefail
worker="${1:?Pass a token from agent-lock worker}"
export AGENT_WORKER_ID="$worker"
build_root=".build/$worker"
mkdir -p "$build_root"
agent-lock run ui -- xcodebuild -project SpamWise.xcodeproj -scheme SpamWise -destination 'platform=macOS,arch=arm64' -derivedDataPath "$build_root/DerivedData" -clonedSourcePackagesDirPath "$build_root/SourcePackages" -allowProvisioningUpdates CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=2NFSK2WB24 CODE_SIGN_IDENTITY="Apple Development" SWIFT_SUPPRESS_WARNINGS=NO -only-testing:UITests test 2>&1 | tee "$build_root/ui.log" | xcbeautify
