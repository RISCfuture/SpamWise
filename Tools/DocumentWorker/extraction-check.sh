#!/bin/bash
#
# Builds and runs the in-process extraction checks, which need no signing identity.
#
#   bash Tools/DocumentWorker/extraction-check.sh <worker-token>

set -euo pipefail
worker="${1:?Pass a token from agent-lock worker}"
build_root=".build/$worker/document-extraction"
mkdir -p "$build_root/cache"
swiftc -swift-version 6 -strict-concurrency=complete -strict-memory-safety -warnings-as-errors \
  -parse-as-library -module-cache-path "$build_root/cache" \
  Tools/DocumentWorker/{Protocol,PDFExtraction,Fixtures,ExtractionChecks}.swift \
  -o "$build_root/ExtractionChecks"
"$build_root/ExtractionChecks" | tee "$build_root/results.log"
