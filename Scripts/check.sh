#!/bin/bash
#
# Runs every offline check a change has to pass: the localization and Help book checks, the
# SpamWiseCore package tests, warning-free unsigned builds of both editions and the Mail
# extension, and the hostless unit tests.
#
#   Scripts/check.sh [build-token]
#
# Products land in .build/<build-token>/ (.build/check/ by default). Pass a different token to keep
# concurrent checks in separate checkouts or sessions from sharing build products.

set -euo pipefail
cd "$(dirname "$0")/.."

token="${1:-check}"
case "$token" in
  *[!a-zA-Z0-9-]*) echo "Build tokens may contain only letters, digits and hyphens." >&2; exit 2 ;;
esac
build_root=".build/$token"
mkdir -p "$build_root"

# Every local Swift package reference must resolve inside the repository.
if grep -En 'relativePath = "?(\.\.(/|"|;)|/)' SpamWise.xcodeproj/project.pbxproj; then
  echo "error: local Swift package references must stay inside the repository" >&2
  exit 1
fi

python3 Scripts/check-core-localizations.py
python3 Scripts/check-help-book.py
swift test --package-path SpamWiseCore --scratch-path "$build_root/swiftpm" \
  -Xswiftc -warnings-as-errors > "$build_root/package.log" 2>&1 \
  || { tail -65 "$build_root/package.log"; exit 1; }
tail -5 "$build_root/package.log"

xcode() {
  xcodebuild -project SpamWise.xcodeproj -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$build_root/DerivedData" \
    -clonedSourcePackagesDirPath "$build_root/SourcePackages" \
    CODE_SIGNING_ALLOWED=NO "$@" 2>&1 | tee -a "$build_root/app.log" | xcbeautify
}

: > "$build_root/app.log"
# Both editions build SpamWise.app into the same products directory, so each is checked right after its build.
for scheme in "SpamWise (MAS)" "SpamWise (download)"; do
  xcode -scheme "$scheme" build
  bash Scripts/check-app-icon.sh "$build_root/DerivedData/Build/Products/Debug/SpamWise.app"
done
xcode -scheme MailExtension build
xcode -scheme "SpamWise Common" test

# Compiler, linker and build-system diagnostics, including Xcode's project- and asset-scoped ones,
# which name an absolute path with no line. Tests that open a corrupt store on purpose make
# CoreData log "error:" lines at runtime, which are not diagnostics.
diagnostic='^((.+:[0-9]+(:[0-9]+)?|/[^:]+): |ld: )?(warning|error): '
if grep -En "$diagnostic" "$build_root/package.log" "$build_root/app.log"; then
  exit 1
fi
