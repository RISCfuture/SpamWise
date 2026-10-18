# Credits

The components below carry their own terms. A summary of these notices also
appears in the app's About panel.

## Apache-2.0 notices

Section 4 of the Apache License 2.0 requires a binary distribution to carry the
license and any NOTICE text, so these are called out explicitly.

- **[ClaudeForFoundationModels](https://github.com/anthropics/ClaudeForFoundationModels)**,
  pinned at revision `0262e1a766c461a4268dcec656eca95dd74cebf8` — Copyright 2026
  Anthropic PBC. Licensed under the Apache License, Version 2.0. The default
  model provider, linked into the app and the Mail extension of both editions.
  The project ships no NOTICE file.
- **[SwiftNIO](https://github.com/apple/swift-nio)** and
  **[swift-nio-imap](https://github.com/apple/swift-nio-imap)** — Copyright
  Apple Inc. and the SwiftNIO project authors. Licensed under the Apache
  License, Version 2.0. The IMAP transport in both editions.
- **[swift-log](https://github.com/apple/swift-log)** — Copyright 2018, 2019
  The SwiftLog Project. Licensed under the Apache License, Version 2.0. Used by
  the download edition only, through GitHubUpdateChecker. Its NOTICE reads:

  > This product contains a derivation of the lock implementation and various
  > scripts from SwiftNIO.
  >
  > - LICENSE (Apache License 2.0): <https://www.apache.org/licenses/LICENSE-2.0>
  > - HOMEPAGE: <https://github.com/apple/swift-nio>

The full text of the Apache License, Version 2.0 is available at
<https://www.apache.org/licenses/LICENSE-2.0>.

## Mozilla Public License 2.0

- **[Public Suffix List](https://publicsuffix.org/list/)** — Mozilla
  Foundation and contributors. Licensed under the Mozilla Public License,
  Version 2.0, <https://mozilla.org/MPL/2.0/>. Bundled unmodified as
  `SpamWiseCore/Sources/MessageModel/Resources/public_suffix_list.dat`, version
  `2026-10-07_07-28-19_UTC` (commit
  `3929462652695bad04f0a27afb600974014a3c8b`), with its license header intact.
  Its source is <https://publicsuffix.org/list/public_suffix_list.dat>.

## Swift packages in the download edition

- [GitHubUpdateChecker](https://github.com/RISCfuture/GitHubUpdateChecker) —
  MIT. Checks GitHub for new releases.
- [swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui) by
  Guillermo Gonzalez — MIT. Via GitHubUpdateChecker.
- [NetworkImage](https://github.com/gonzalezreal/NetworkImage) by Guille
  Gonzalez — MIT. Via swift-markdown-ui.
- [swift-cmark](https://github.com/swiftlang/swift-cmark) — BSD 2-Clause,
  Copyright © 2014 John MacFarlane. Via swift-markdown-ui. Portions derived
  from houdini, GitHub's buffer code and utf8proc are MIT.

The App Store edition links none of these.

Every version is pinned in `SpamWiseCore/Package.resolved` and
`SpamWise.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

## Anthropic

SpamWise is an independent app. It is **not affiliated with, endorsed by, or
sponsored by Anthropic**. Claude is a trademark of Anthropic PBC.
