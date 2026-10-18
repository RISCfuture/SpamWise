#!/bin/bash
set -euo pipefail
worker="${1:?Pass a token from agent-lock worker}"
export AGENT_WORKER_ID="$worker"
build_root=".build/$worker"
mkdir -p "$build_root"
swiftc -swift-version 6 -strict-concurrency=complete -strict-memory-safety -warnings-as-errors \
  -package-name SpamWiseCore -parse-as-library \
  SpamWiseCore/Sources/Store/Store.swift SpamWiseCore/Sources/Store/Schema.swift \
  Scripts/store-probe.swift -o "$build_root/store-probe"
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
