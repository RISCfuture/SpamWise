#!/bin/bash
set -euo pipefail
worker="${1:?Pass a token from agent-lock worker}"
export AGENT_WORKER_ID="$worker"
build_root=".build/$worker"

# Every local Swift package reference must resolve inside the repository.
if rg -n 'relativePath = "?(\.\.(/|"|;)|/)' SpamWise.xcodeproj/project.pbxproj; then
  echo "error: local Swift package references must stay inside the repository" >&2
  exit 1
fi

mkdir -p "$build_root"
python3 Scripts/check-core-localizations.py
swift test --package-path SpamWiseCore --scratch-path "$build_root/swiftpm" -Xswiftc -warnings-as-errors > "$build_root/package.log" 2>&1 || { tail -65 "$build_root/package.log"; exit 1; }
tail -5 "$build_root/package.log"
xcodebuild -project SpamWise.xcodeproj -scheme SpamWise -destination 'platform=macOS,arch=arm64' -derivedDataPath "$build_root/DerivedData" -clonedSourcePackagesDirPath "$build_root/SourcePackages" CODE_SIGNING_ALLOWED=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES SWIFT_SUPPRESS_WARNINGS=NO build 2>&1 | tee "$build_root/app.log" | xcbeautify
if rg -n 'warning:|error:' "$build_root/package.log" "$build_root/app.log"; then exit 1; fi
bash Scripts/check-app-icon.sh "$build_root/DerivedData/Build/Products/Debug/SpamWise.app"
