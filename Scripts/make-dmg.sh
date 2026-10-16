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
rm -f "$dmg"

# hdiutil refuses to overwrite, and a stale staging directory would ship whatever it holds.
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

ditto "$app" "$stage/$(basename "$app")"
ln -s /Applications "$stage/Applications"

hdiutil create -volname "SpamWise $version" -srcfolder "$stage" -ov -format UDZO "$dmg" >/dev/null

echo "$dmg"
