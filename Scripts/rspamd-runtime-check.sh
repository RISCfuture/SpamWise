#!/bin/bash
set -euo pipefail
worker="${1:?Pass a token from agent-lock worker}"
source_root="${2:?Pass the absolute Rspamd source directory}"
rspamd_build="${3:?Pass the absolute Rspamd build directory}"
probe="${4:?Pass the absolute unsandboxed evidence probe executable}"
signed_probe="${5:?Pass the absolute sandboxed evidence probe executable}"
export AGENT_WORKER_ID="$worker"
evidence_root="$PWD/.build/$worker/rspamd"
mkdir -p "$evidence_root"
runtime="$(mktemp -d "$evidence_root/runtime.XXXXXX")"
daemon_pid=""
fixture_pid=""
cleanup() {
  if [[ -n "$fixture_pid" ]]; then
    kill "$fixture_pid" 2>/dev/null || true
    wait "$fixture_pid" 2>/dev/null || true
  fi
  if [[ -n "$daemon_pid" ]]; then
    kill "$daemon_pid" 2>/dev/null || true
    wait "$daemon_pid" 2>/dev/null || true
  fi
  for path in "$runtime"/*; do
    if [[ -f "$path" || -S "$path" ]]; then unlink "$path"; fi
  done
  rmdir "$runtime"
}
trap cleanup EXIT
if lsof -nP -iTCP:11333 -iTCP:11334 -sTCP:LISTEN >/dev/null 2>&1; then
  echo 'Port 11333 or 11334 is already occupied; refusing to change an existing service.' >&2
  exit 1
fi
swiftc -swift-version 6 -strict-concurrency=complete -strict-memory-safety -warnings-as-errors \
  -parse-as-library -module-cache-path "$PWD/.build/$worker/cache" \
  Scripts/rspamd-http-fixture.swift -o "$evidence_root/http-fixture"
"$evidence_root/http-fixture" > "$evidence_root/http-fixture.log" 2>&1 &
fixture_pid=$!
ready=false
for _ in {1..50}; do
  if ! kill -0 "$fixture_pid" 2>/dev/null; then cat "$evidence_root/http-fixture.log" >&2; exit 1; fi
  if rg -q 'ready 11333' "$evidence_root/http-fixture.log" && \
    rg -q 'ready 11334' "$evidence_root/http-fixture.log"; then ready=true; break; fi
  sleep 0.1
done
if [[ "$ready" != true ]]; then echo 'HTTP fixture did not become ready.' >&2; exit 1; fi
"$signed_probe" rspamd-http-faults > "$evidence_root/http-faults.log" 2>&1
cat "$evidence_root/http-faults.log"
if rg -q 'redirect-received|invalid-request|failed ' "$evidence_root/http-fixture.log"; then
  cat "$evidence_root/http-fixture.log" >&2
  exit 1
fi
for expected in redirect-sent overflow-sent failure-sent timeout-closed cancel-closed marker-sent ordinary-sent; do
  if ! rg -q "^$expected$" "$evidence_root/http-fixture.log"; then
    echo "Missing HTTP fixture observation: $expected" >&2
    exit 1
  fi
done
kill "$fixture_pid"
wait "$fixture_pid" || true
fixture_pid=""
if lsof -nP -iTCP:11333 -iTCP:11334 -sTCP:LISTEN >/dev/null 2>&1; then
  echo 'Fixture port remains occupied after cleanup.' >&2
  exit 1
fi
cat > "$runtime/rspamd.conf" <<CONFIG
options {
  filters = ["regexp"];
  explicit_modules = [];
  url_tld = "$source_root/test/lua/unit/test_tld.dat";
  lua_path = "$source_root/lualib/?.lua";
  pidfile = "$runtime/rspamd.pid";
  tempdir = "$runtime";
  dns { nameserver = "127.0.0.1:9"; retransmits = 1; timeout = 0.1s; }
}
logging { type = "console"; level = "info"; }
metric { name = "default"; actions { reject = 100; } }
worker {
  type = "normal";
  bind_socket = "127.0.0.1:11333";
  count = 1;
  task_timeout = 2s;
  allow_file_and_shm_inputs = false;
}
regexp {
  SPAMWISE_PROBE {
    re = '/spamwiseprobe/{sa_body}';
    score = 1.5;
    description = 'Synthetic integration fixture';
  }
}
CONFIG
cat > "$runtime/network.sb" <<'PROFILE'
(version 1)
(allow default)
(deny network*)
(allow network-inbound (local ip "localhost:11333"))
(allow network-outbound (remote ip "localhost:*"))
PROFILE
lua_path="$source_root/contrib/lua-fun/?.lua;$source_root/contrib/lua-argparse/?.lua"
lua_path+=";$source_root/contrib/lua-lupa/?.lua;$source_root/contrib/lua-lpeg/?.lua;;"
LUA_PATH="$lua_path" LUALIBDIR="$source_root/lualib" RULESDIR="$source_root/rules" \
  /usr/bin/sandbox-exec -f "$runtime/network.sb" \
  "$rspamd_build/src/rspamd" -f -T -c "$runtime/rspamd.conf" \
  > "$evidence_root/daemon.log" 2>&1 &
daemon_pid=$!
ready=false
for _ in {1..50}; do
  if ! kill -0 "$daemon_pid" 2>/dev/null; then
    cat "$evidence_root/daemon.log" >&2
    exit 1
  fi
  if nc -z -w 1 127.0.0.1 11333; then ready=true; break; fi
  sleep 0.1
done
if [[ "$ready" != true ]]; then
  echo 'Temporary Rspamd did not become ready.' >&2
  exit 1
fi
lsof -nP -iTCP:11333 -sTCP:LISTEN > "$evidence_root/listener.log"
"$probe" rspamd-http observed > "$evidence_root/http.log" 2>&1
cat "$evidence_root/http.log"
"$signed_probe" rspamd-http observed > "$evidence_root/signed-http.log" 2>&1
cat "$evidence_root/signed-http.log"
kill "$daemon_pid"
wait "$daemon_pid" || true
daemon_pid=""
"$signed_probe" rspamd-http unknown > "$evidence_root/stopped-http.log" 2>&1
cat "$evidence_root/stopped-http.log"
if lsof -nP -iTCP:11333 -sTCP:LISTEN >/dev/null 2>&1; then
  echo 'Port 11333 remains occupied after cleanup.' >&2
  exit 1
fi
