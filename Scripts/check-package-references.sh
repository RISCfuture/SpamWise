#!/bin/bash
#
# Fails when a local Swift package reference in the Xcode project resolves outside the repository.
#
#   Scripts/check-package-references.sh

set -euo pipefail
cd "$(dirname "$0")/.."

if grep -En 'relativePath = "?(\.\.(/|"|;)|/)' SpamWise.xcodeproj/project.pbxproj; then
  echo "error: local Swift package references must stay inside the repository" >&2
  exit 1
fi
