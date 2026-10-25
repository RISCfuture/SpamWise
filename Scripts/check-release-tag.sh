#!/bin/bash
#
# Fails when the release tag already exists and names a commit other than the one this run builds,
# or when GitHub can't say whether the tag exists.
#
#   Scripts/check-release-tag.sh <version>
#
# Reads GH_TOKEN, GITHUB_REPOSITORY and GITHUB_SHA from the Actions environment. A tag that does
# not exist yet passes: the GitHub release creates it on GITHUB_SHA.

set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $(basename "$0") <version>" >&2
  exit 2
fi

version="$1"

# The version becomes part of an API path, so only a release version reaches it.
if ! [[ $version =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
  echo "::error::$version is not a release version such as 1.2 or 1.2.3."
  exit 1
fi

# Only a confirmed 404 means the tag is missing; any other API error stops the run.
if errors=$(gh api "repos/$GITHUB_REPOSITORY/git/ref/tags/$version" --silent 2>&1); then
  tagged=$(gh api "repos/$GITHUB_REPOSITORY/commits/refs/tags/$version" --jq .sha)
  if [ "$tagged" != "$GITHUB_SHA" ]; then
    echo "::error::Tag $version points at $tagged, but this run builds $GITHUB_SHA."
    exit 1
  fi
elif [[ $errors != *"(HTTP 404)"* ]]; then
  echo "::error::Couldn't check whether tag $version exists: $errors"
  exit 1
fi
