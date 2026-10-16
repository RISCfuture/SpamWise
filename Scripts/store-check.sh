#!/bin/bash
#
# Verifies the Store's cross-process transactions: two processes make 50 atomic increments each
# and a third reads 100.
#
#   Scripts/store-check.sh [build-token]
#
# Products land in .build/<build-token>/ (.build/check/ by default).

set -euo pipefail
cd "$(dirname "$0")/.."

token="${1:-check}"
case "$token" in
  *[!a-zA-Z0-9-]*) echo "Build tokens may contain only letters, digits and hyphens." >&2; exit 2 ;;
esac
build_root=".build/$token"
mkdir -p "$build_root"
swiftc -swift-version 6 -strict-concurrency=complete -strict-memory-safety -warnings-as-errors \
  -package-name SpamWiseCore -parse-as-library \
  SpamWiseCore/Sources/Store/Store.swift SpamWiseCore/Sources/Store/Schema.swift \
  Scripts/store-probe-bundle.swift Scripts/store-probe.swift -o "$build_root/store-probe"
probe_dir="$(mktemp -d "$build_root/store-test.XXXXXX")"
trap 'rm -rf "$probe_dir"' EXIT
"$build_root/store-probe" "$probe_dir/state.store" 0
"$build_root/store-probe" "$probe_dir/state.store" 50 &
first_pid=$!
"$build_root/store-probe" "$probe_dir/state.store" 50 &
second_pid=$!
wait "$first_pid"
wait "$second_pid"
count="$("$build_root/store-probe" "$probe_dir/state.store" read)"
[[ "$count" == 100 ]]
echo "Two Store processes committed 100 atomic increments; third-process read verified."
