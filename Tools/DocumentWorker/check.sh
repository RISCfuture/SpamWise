#!/bin/bash
set -euo pipefail
worker="${1:?Pass a token from agent-lock worker}"
identity="${2:?Pass a Developer ID Application identity}"
export AGENT_WORKER_ID="$worker"
bash Tools/DocumentWorker/extraction-check.sh "$worker"
build_root=".build/$worker/document-worker"
host="$build_root/DocumentProbe.app"
service="$host/Contents/XPCServices/DocumentWorker.xpc"
mkdir -p "$host/Contents/MacOS" "$service/Contents/MacOS" "$build_root/cache"
common=(-swift-version 6 -strict-concurrency=complete -strict-memory-safety -warnings-as-errors -parse-as-library -module-cache-path "$build_root/cache")
swiftc "${common[@]}" -D DOCUMENT_WORKER_PROBE Tools/DocumentWorker/{Protocol,PDFExtraction,Worker,WorkerProbes}.swift -o "$service/Contents/MacOS/DocumentWorker"
swiftc "${common[@]}" -D DOCUMENT_WORKER_PROBE Tools/DocumentWorker/{Protocol,Client,Fixtures,ProbeHost}.swift -o "$host/Contents/MacOS/DocumentProbe"
cat > "$service/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>codes.tim.SpamWise.DocumentWorker</string>
<key>CFBundleExecutable</key><string>DocumentWorker</string>
<key>CFBundlePackageType</key><string>XPC!</string>
<key>CFBundleVersion</key><string>1</string>
<key>XPCService</key><dict><key>ServiceType</key><string>Application</string><key>RunLoopType</key><string>dispatch_main</string></dict>
</dict></plist>
PLIST
cat > "$host/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>codes.tim.SpamWise.DocumentProbe</string>
<key>CFBundleExecutable</key><string>DocumentProbe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
cat > "$build_root/worker.entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>com.apple.security.app-sandbox</key><true/></dict></plist>
PLIST
cat > "$build_root/host.entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>com.apple.security.app-sandbox</key><true/><key>com.apple.security.network.client</key><true/></dict></plist>
PLIST
codesign --force --options runtime --timestamp --sign "$identity" --entitlements "$build_root/worker.entitlements" "$service"
codesign --force --options runtime --timestamp --sign "$identity" --entitlements "$build_root/host.entitlements" "$host"
codesign --verify --deep --strict "$host"
"$host/Contents/MacOS/DocumentProbe" | tee "$build_root/results.log"

sentinel="$PWD/$build_root/host-only.txt"
printf 'Synthetic sandbox sentinel\n' > "$sentinel"
port=39864
if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null; then
  echo "The loopback probe port $port is already occupied." >&2
  exit 1
fi
nc -lk 127.0.0.1 "$port" >/dev/null &
listener_pid=$!
cleanup() {
  kill "$listener_pid" 2>/dev/null || true
  wait "$listener_pid" 2>/dev/null || true
  if [[ -e "$sentinel" ]]; then unlink "$sentinel"; fi
}
trap cleanup EXIT
for _ in {1..50}; do
  if nc -z 127.0.0.1 "$port"; then break; fi
  sleep 0.02
done
nc -z 127.0.0.1 "$port"
"$host/Contents/MacOS/DocumentProbe" --access "$sentinel" "$port" | tee "$build_root/sandbox.log"
cleanup
trap - EXIT

unauthorized="$build_root/UnauthorizedProbe.app"
ditto "$host" "$unauthorized"
plutil -replace CFBundleIdentifier -string codes.tim.SpamWise.UnauthorizedProbe "$unauthorized/Contents/Info.plist"
codesign --force --options runtime --timestamp --sign "$identity" --entitlements "$build_root/host.entitlements" "$unauthorized"
"$unauthorized/Contents/MacOS/DocumentProbe" --unauthorized | tee "$build_root/unauthorized.log"

production="$build_root/ProductionProbe.app"
ditto "$host" "$production"
production_service="$production/Contents/XPCServices/DocumentWorker.xpc"
swiftc "${common[@]}" Tools/DocumentWorker/{Protocol,PDFExtraction,Worker}.swift -o "$production_service/Contents/MacOS/DocumentWorker"
codesign --force --options runtime --timestamp --sign "$identity" --entitlements "$build_root/worker.entitlements" "$production_service"
codesign --force --options runtime --timestamp --sign "$identity" --entitlements "$build_root/host.entitlements" "$production"
codesign --verify --deep --strict "$production"
"$production/Contents/MacOS/DocumentProbe" --smoke | tee "$build_root/production.log"
if nm "$production_service/Contents/MacOS/DocumentWorker" | rg 'WorkerProbes|exercise'; then
  echo 'Production worker contains diagnostic entry points.' >&2
  exit 1
fi
