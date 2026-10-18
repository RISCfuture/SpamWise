#!/bin/bash
#
# Rebuilds the Help book's search index for each localization, then lints the book's and the
# editions' Info.plists. The release lanes run this before archiving.
#
#   Scripts/help-index.sh

set -euo pipefail
cd "$(dirname "$0")/.."

for book in SpamWise/SpamWise.help/Contents/Resources/*.lproj; do
  language="${book##*/}"
  language="${language%.lproj}"
  hiutil -I corespotlight -C -a -s "$language" -l "$language" -f "$book/search.cshelpindex" "$book"
done
plutil -lint SpamWise/SpamWise.help/Contents/Info.plist SpamWise-MAS/Info.plist \
  SpamWise-download/Info.plist
