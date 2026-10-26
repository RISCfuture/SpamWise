#!/bin/bash
#
# Packages the notarized, stapled download edition into a disk image for the GitHub release.
#
#   Scripts/make-dmg.sh <path/to/SpamWise.app> <version> <output-directory>
#
# Produces "<output-directory>/SpamWise-<version>.dmg" and prints its path. The image holds the app
# and a symlink to /Applications, which is the whole of the expected drag-to-install gesture.
#
# This script only packages. The caller signs, notarizes and staples the image afterwards: a
# downloaded image is quarantined and judged by Gatekeeper on its own merits, so notarizing the app
# inside it is not enough.

set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "usage: $(basename "$0") <app-path> <version> <output-directory>" >&2
  exit 2
fi

app="$1"
version="$2"
output_directory="$3"

[ -d "$app" ] || { echo "error: no app bundle at $app" >&2; exit 1; }
xcrun stapler validate "$app" >/dev/null \
  || { echo "error: $app carries no stapled notarization ticket" >&2; exit 1; }

mkdir -p "$output_directory"
dmg="$output_directory/SpamWise-$version.dmg"

# A fresh staging directory, because a stale one would ship whatever it holds.
stage="$(mktemp -d)"
log="$(mktemp)"
trap 'rm -rf "$stage" "$log"' EXIT

ditto "$app" "$stage/$(basename "$app")"
ln -s /Applications "$stage/Applications"

# The path is this script's only output, so diskutil's progress is shown only when imaging fails.
diskutil image create from --format UDZO --volumeName "SpamWise $version" "$stage" "$dmg" \
  >/dev/null 2>"$log" || { cat "$log" >&2; exit 1; }

echo "$dmg"
