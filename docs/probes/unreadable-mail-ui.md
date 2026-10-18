# Unreadable-mail UI inspection

## Settings navigation

The development-signed Debug app was launched as a separate process with
`--ui-testing --ui-visual-fixture -AppleLanguages '(en)'`. Its fixture uses
temporary storage and a denied Apple Events boundary. The intended scan-health
fixture contains three unreadable messages and 20 visited positions out of 30.

Native accessibility inspection reached
Settings → Accounts and exposed the “Accounts and scan health” disclosure.
Setting the scroll bar through Accessibility successfully revealed that control.

The disclosure could not be expanded. A pre-existing macOS
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

This inspection made no Mail requests or paid API calls and changed no production
settings. Readability of the status inside the full Settings navigation remains
unverified.
