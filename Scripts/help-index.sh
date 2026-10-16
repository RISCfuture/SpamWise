#!/bin/bash
set -euo pipefail
book="SpamWise/SpamWise.help/Contents/Resources/en.lproj"
hiutil -I corespotlight -C -a -s en -f "$book/search.cshelpindex" "$book"
plutil -lint SpamWise/SpamWise.help/Contents/Info.plist SpamWise/Info.plist
