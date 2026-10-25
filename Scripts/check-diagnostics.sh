#!/bin/bash
#
# Fails when a build or test log holds a compiler, linker or build-system diagnostic, including
# Xcode's project- and asset-scoped ones, which name an absolute path with no line. Tests that open
# a corrupt store on purpose make CoreData log "error:" lines at runtime, which are not diagnostics.
#
#   Scripts/check-diagnostics.sh <log>...

set -euo pipefail

if [ "$#" -eq 0 ]; then
  echo "usage: $0 <log>..." >&2
  exit 2
fi

for log in "$@"; do
  [ -r "$log" ] || { echo "error: no log at $log" >&2; exit 2; }
done

diagnostic='^((.+:[0-9]+(:[0-9]+)?|/[^:]+): |ld: )?(warning|error): '
if grep -En "$diagnostic" "$@"; then
  echo "error: the logs above report build diagnostics" >&2
  exit 1
fi
