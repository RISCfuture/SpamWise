# Unreadable-mail UI inspection

## 2026-10-16 attempt

The development-signed Debug app was launched as a separate process with
`--ui-testing --ui-visual-fixture -AppleLanguages '(en)'`. Its fixture uses
temporary storage and a denied Apple Events boundary. The intended scan-health
fixture contains three unreadable messages and 20 visited positions out of 30.

The exact build was
`.build/5464e5b9-9f33-4901-b002-8686c83306da/DerivedData/Build/Products/Debug/SpamWise.app`.
The inspected process was PID 24322. Native accessibility inspection reached
Settings → Accounts and exposed the “Accounts and scan health” disclosure.
Setting the scroll bar through Accessibility successfully revealed that control.

The disclosure could not be expanded during this attempt. A pre-existing macOS
Screenshot overlay intercepted scrolling and pixel clicks, including foreground
delivery. Escape did not dismiss that persistent overlay. The disclosure exposed
no press action; setting its accessibility value and disclosing attributes did
not change its collapsed state. This is an automation limitation, not evidence
that the application control fails for a person.

The English screen before expansion was captured, with no visible overlap or
clipping in the exposed Mail connection section. The unreadable-mail status and
explanatory copy were not visible, so their readability is **unverified**.
Spanish and French inspection of the Settings flow was not attempted after the
navigation blocker.

## Direct component previews

Xcode rendered `UnreadableMailView`'s “Incomplete sweep” preview sequentially in
English, Spanish, and French on macOS 27.0.1. All three render operations succeeded
without reported errors, and the localized text and count of three appeared.
The plain Form preview has no explicit width or padding. Its snapshot clips the
Spanish and French text at the left and right edges. The English explanation
also reaches the right edge. These snapshots do not establish readable layout
inside the actual Settings form; they expose a preview-container limitation
that required a constrained preview before visual acceptance.

The preview container was then changed to a grouped Form measuring 600 × 180
points, matching the Settings form style. The production component was unchanged.
Fresh sequential renders in all three languages show the count **3**, the full
localized label, and the full explanation without overlap or clipping. Spanish
wraps the explanation to two lines; English and French fit on one line. This
verifies the component in that container, not the complete Settings navigation
or the 20-of-30 scan-progress status.

Observed labels were “Unreadable messages”, “Mensajes ilegibles”, and
“Messages illisibles”. The explanatory text reads:

- English: “Unreadable mail stays in place and is retried on the next sweep.”
- Spanish: “Los mensajes ilegibles permanecen en su sitio y se vuelven a intentar
  en el próximo recorrido.”
- French: “Les messages illisibles restent en place et seront réessayés au
  prochain parcours.”

Evidence, relative to the repository root:

- `.build/76c96ab1-49e2-460a-bd4c-1f28fb0d4b58/en-accounts-blocked.jpg`
- `.build/76c96ab1-49e2-460a-bd4c-1f28fb0d4b58/en-accounts-blocked.txt`
- `.build/76c96ab1-49e2-460a-bd4c-1f28fb0d4b58/en-unreadable-preview.png`
- `.build/76c96ab1-49e2-460a-bd4c-1f28fb0d4b58/es-unreadable-preview.png`
- `.build/76c96ab1-49e2-460a-bd4c-1f28fb0d4b58/fr-unreadable-preview.png`
- `.build/76c96ab1-49e2-460a-bd4c-1f28fb0d4b58/en-unreadable-final.png`
- `.build/76c96ab1-49e2-460a-bd4c-1f28fb0d4b58/es-unreadable-final.png`
- `.build/76c96ab1-49e2-460a-bd4c-1f28fb0d4b58/fr-unreadable-final.png`

Matching `en-preview-metadata.json`, `es-preview-metadata.json`, and
`fr-preview-metadata.json` files record the Xcode render responses in that
artifact directory.
The corresponding `en-final-metadata.json`, `es-final-metadata.json`, and
`fr-final-metadata.json` files record the final renders.

This inspection made no Mail requests or paid API calls and changed no
production settings. Only the separately launched fixture process was closed.
The parent session performs the package, build, and lint verification.
