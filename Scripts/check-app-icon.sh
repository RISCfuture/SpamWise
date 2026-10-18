#!/bin/bash
# Fails unless each app bundle carries the compiled AppIcon that Finder, the Dock and App Store validation read.
set -euo pipefail
if [[ $# -eq 0 ]]; then
  echo 'Usage: bash Scripts/check-app-icon.sh APP...' >&2
  exit 2
fi
for app in "$@"; do
  if [[ ! -s "$app/Contents/Resources/Assets.car" ]]; then
    echo "Missing compiled asset catalog: $app/Contents/Resources/Assets.car" >&2
    exit 1
  fi
  icon_name=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$app/Contents/Info.plist" 2>/dev/null || true)
  if [[ "$icon_name" != AppIcon ]]; then
    echo "CFBundleIconName is '${icon_name}', expected AppIcon: $app" >&2
    exit 1
  fi
  echo "App icon present: $app"
done
