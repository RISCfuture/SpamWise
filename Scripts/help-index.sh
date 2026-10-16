#!/bin/bash
set -euo pipefail
for book in SpamWise/SpamWise.help/Contents/Resources/*.lproj; do
  language="${book##*/}"
  language="${language%.lproj}"
  hiutil -I corespotlight -C -a -s "$language" -l "$language" -f "$book/search.cshelpindex" "$book"
done
plutil -lint SpamWise/SpamWise.help/Contents/Info.plist SpamWise/Info.plist
