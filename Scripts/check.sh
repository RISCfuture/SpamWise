#!/bin/bash
set -euo pipefail
swift test --package-path SpamWiseCore --scratch-path /tmp/SpamWise-package -Xswiftc -warnings-as-errors > /tmp/SpamWise-package.log 2>&1 || { tail -65 /tmp/SpamWise-package.log; exit 1; }
tail -5 /tmp/SpamWise-package.log
xcodebuild -project SpamWise.xcodeproj -scheme SpamWise -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/SpamWise-build CODE_SIGNING_ALLOWED=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES build > /tmp/SpamWise-app.log 2>&1 || { tail -65 /tmp/SpamWise-app.log; exit 1; }
if rg -n 'warning:|error:' /tmp/SpamWise-package.log /tmp/SpamWise-app.log; then exit 1; fi
tail -3 /tmp/SpamWise-app.log
