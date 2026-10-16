#!/bin/bash
#
# Builds a Developer ID signed, sandboxed evidence probe app and records its network activity while
# it runs the OCR and privacy cases.
#
#   Scripts/evidence-runtime-check.sh <signing-identity> [build-token]
#
# Products and logs land in .build/<build-token>/ (.build/check/ by default).

set -euo pipefail
cd "$(dirname "$0")/.."

identity="${1:?Pass a Developer ID Application signing identity}"
token="${2:-check}"
case "$token" in
  *[!a-zA-Z0-9-]*) echo "Build tokens may contain only letters, digits and hyphens." >&2; exit 2 ;;
esac
build_root=".build/$token"
app="$build_root/SpamWiseEvidenceProbe.app"
contents="$app/Contents"
mkdir -p "$contents/MacOS" "$contents/Resources"
swift build --package-path SpamWiseCore --scratch-path "$build_root/swiftpm" \
  -Xswiftc -warnings-as-errors > "$build_root/evidence-build.log" 2>&1
products="$build_root/swiftpm/debug"
swiftc -swift-version 6 -strict-concurrency=complete -strict-memory-safety -warnings-as-errors \
  -parse-as-library -module-cache-path "$build_root/cache" -I "$products" -L "$products" \
  -Xcc -fmodule-map-file=SpamWiseCore/Sources/CResolver/module.modulemap \
  -lSpamWiseCore Scripts/evidence-runtime-probe.swift -o "$contents/MacOS/SpamWiseEvidenceProbe"
cp -R "$products/SpamWiseCore_MessageModel.bundle" "$contents/Resources/"
cat > "$contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>codes.tim.SpamWise.EvidenceProbe</string>
<key>CFBundleExecutable</key><string>SpamWiseEvidenceProbe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
cat > "$build_root/evidence-entitlements.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>com.apple.security.app-sandbox</key><true/>
<key>com.apple.security.network.client</key><true/>
</dict></plist>
PLIST
codesign --force --options runtime --timestamp --sign "$identity" \
  --entitlements "$build_root/evidence-entitlements.plist" "$app"
codesign --verify --deep --strict "$app"

probe_pid=""
observer_pid=""
cleanup() {
  if [[ -n "$probe_pid" ]]; then kill "$probe_pid" 2>/dev/null || true; fi
  if [[ -n "$observer_pid" ]]; then kill "$observer_pid" 2>/dev/null || true; fi
}
trap cleanup EXIT
for mode in ocr privacy; do
  "$contents/MacOS/SpamWiseEvidenceProbe" "$mode" > "$build_root/$mode.log" 2>&1 &
  probe_pid=$!
  nettop -P -n -L 0 -p "$probe_pid" -J bytes_in,bytes_out > "$build_root/$mode-network.csv" 2>&1 &
  observer_pid=$!
  wait "$probe_pid"
  probe_pid=""
  kill "$observer_pid" 2>/dev/null || true
  wait "$observer_pid" 2>/dev/null || true
  observer_pid=""
  cat "$build_root/$mode.log"
done
