#!/bin/bash
#
# Builds and runs the in-process extraction checks, which need no signing identity.
#
#   bash Tools/DocumentWorker/extraction-check.sh [build-token]
#
# Results land in .build/<build-token>/document-extraction/ (.build/check/ by default).

set -euo pipefail
cd "$(dirname "$0")/../.."

token="${1:-check}"
case "$token" in
  *[!a-zA-Z0-9-]*) echo "Build tokens may contain only letters, digits and hyphens." >&2; exit 2 ;;
esac
build_root=".build/$token/document-extraction"
mkdir -p "$build_root/cache"
swiftc -swift-version 6 -strict-concurrency=complete -strict-memory-safety -warnings-as-errors \
  -parse-as-library -module-cache-path "$build_root/cache" \
  Tools/DocumentWorker/{Protocol,PDFExtraction,Fixtures,ExtractionChecks}.swift \
  -o "$build_root/ExtractionChecks"
"$build_root/ExtractionChecks" | tee "$build_root/results.log"
