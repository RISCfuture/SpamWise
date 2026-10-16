# Conventions and design review

Reviewed 2026-10-16 against baseline `6d813c1` on `codex/phase-one`.

## Sources and scope

The authoritative conventions are the `swift-conventions` and `swiftui-conventions`
skills in `~/Repositories/shell-files/dotfiles/agents/skills/`. Every project-owned
Swift source, test, executable script, AppleScript, Help HTML and stylesheet is
listed below. Vendor packages, generated build output, fixture messages and the
bundled Public Suffix List are data/dependencies, not rewritten application code.
The Xcode configuration, package manifest, SwiftLint configuration, entitlements,
resource registration and localization catalog were also reviewed.

Apple’s [Settings](https://developer.apple.com/design/human-interface-guidelines/settings),
[toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars),
[layout](https://developer.apple.com/design/human-interface-guidelines/layout),
[disclosure controls](https://developer.apple.com/design/human-interface-guidelines/disclosure-controls)
and [onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding)
guidance informed the design pass.

## Implemented changes

- Activity uses a native toolbar, a compact table and an inspector. Corrections stay
  visible; evidence, usage and action diagnostics sit behind a disclosure. Status
  footers occupy separate layout space instead of overlapping scrollable forms.
- Settings separates General, Accounts, Rules, Preferences and Advanced. Connection
  and provider controls appear only when relevant. Native Help buttons replace
  repeated explanatory links. The app remembers the selected pane.
- First launch presents four offline-capable steps in the main window; Settings
  can reopen setup in a sheet. Both use consistent Back/Continue navigation and concise privacy information. Error and permission feedback remains
  visible when applicable.
- View composition uses concrete subview types and injected previews. UI state and
  asynchronous connection work are separated. Swift declaration ordering is now an
  enforced lint rule; production bounds have names; public APIs have DocC comments;
  errors expose localized categories and reasons.
- Swift Testing cases use prose identifiers. XCTest keeps typed screen objects,
  stable application identifiers and predicate waits for whole flows. Spanish and
  French translations cover the revised interface and localized errors.

## Compatibility decisions

Public/persisted signed integer fields retain their established interfaces and
negative-input validation. Collection indices stay `Int`. Protocol bytes, schemas,
HTTP codes, pricing tables and mathematical identities remain literal domain data.
Model prompts, cache identities, stored keys and machine-readable reports retain
stable vocabulary; localized presentation is handled at the app boundary.

The lock-protected legacy completion bridge retains its documented
`@unchecked Sendable` boundary. Narrow C/Objective-C interop remains explicitly
`unsafe`. Native Settings toolbar tabs do not expose SwiftUI identifiers, so the
XCTest Settings screen pins English for that one system-provided locator; app
controls use stable identifiers. The package is an app/tool package with no external
library compatibility promise and retains Swift 6 mode.

## View verification

All 27 view types were inspected in native UI. Evidence stems refer to screenshots
and accessibility captures in
`.build/3fd3b409-633f-494a-8220-afc7729009b6/ui-visual/`.
The matrix covers representative branches, not every provider/locale permutation.
Native table columns scroll horizontally with the inspector open at narrow widths.

| View or representable | Evidence and observed branches |
| --- | --- |
| ContentView | `es-setup-intro`, `es-activity-empty-narrow`: initial setup transitions to Activity |
| ActivityView | `en-fixture-activity`, `fr-activity`, `es-activity-empty-narrow`: populated/empty; narrow toolbar overflow |
| ActivityStatusView | `es-activity-paused-narrow`, `final-corrections`: dry-run, paused and synthetic validated-account modes |
| OnboardingView | `es-setup-*-narrow`, `final-setup-sheet-*`: all four inline/sheet steps and completion |
| SetupIntroductionView | `es-setup-intro-narrow`, `final-setup-sheet-intro`: localized privacy text and Help |
| KeyEntryView | `en-accounts`, `es-setup-key-narrow`, `final-setup-sheet-key`: empty secure field, disabled Verify |
| MailConnectionView | `en-mail-history-bottom`, `es-setup-mail-denied-narrow`, `fr-accounts-denied-bottom`: initial/denied, History/Contacts |
| MailActionSetupView | `en-mail-actions`: instructions, zero validated accounts and controls |
| SetupPreviewView | `es-setup-preview-narrow`, `final-setup-sheet-preview`: offline instructions and Finish |
| SettingsView | `en-settings-general`, `es-general-narrow`, `fr-general`: five native toolbar panes |
| GeneralSettingsView | `fr-general`, `final-general`: localized filtering/review controls and Help alignment |
| AccountSettingsView | `en-accounts`, `en-imap`, `fr-accounts-denied-bottom`: Mail/IMAP and clear status footer |
| ModelSettingsView | `en-provider-*`, `en-usage-expanded`: all five providers and usage/spending |
| IMAPSettingsView | `en-imap-options`, `en-imap-actions`: all fields/options/actions; no save/check/probe |
| RuleEditorView | `en-rules-initial`, `en-rules-selected`, `es-rules`, `fr-rules`: empty/populated/selected |
| RuleFormView | `en-rule-add`, `en-rule-edit`, `fr-rule-add`: add/edit; fixed existing identity; synthetic address saved |
| PolicyView | `en-preferences`, `es-preferences`, `fr-preferences`: localized defaults/counts/buttons |
| AdvancedSettingsView | `en-context` through `en-integration-details`, `fr-advanced`: five expandable groups and scrolling |
| LearningSettingsView | `en-learning`, `en-evaluation`, `fr-learning`: toggles, evaluation retention/export |
| DomainSuggestionsView | `en-learning`, `fr-learning`: populated shop.example suggestion |
| EvidenceSettingsView | `en-evidence`, `en-evidence-dbl`, `fr-evidence`: DBL off/on conditional fields; draft only |
| ReviewDigestView | `en-digest-populated`, `es-activity-afterdigest`: populated/empty sheets |
| DecisionDetailView | `en-inspector-failed`, `fr-review-inspector`, `final-inspector`: failed Junk, Review and evidence-bearing Junk |
| CorrectionControls | `final-domain-menu`: Good/Junk/Review controls; active explicit-domain Allow/Block menu |
| DecisionDiagnosticsView | `final-evidence-top`, `final-evidence-bottom`: all metrics and full evidence JSON reachable |
| VerdictBadge | Junk/Review variants in populated Activity; Good/unclassified not fixture-provided |
| HelpButton | Accessible native Help labels/icons across setup, Settings and inspector; no external navigation |

## File-by-file audit

140 project-owned code files assessed. “Reviewed unchanged” is an explicit
inspection result, not an omitted file.

| File | Assessment |
| --- | --- |
| `MailExtension/MailExtension.swift` | Removed generated file header; documented nonisolated Mail XPC entry point; implicit single-expression return. |
| `MailExtension/MessageActionHandler.swift` | Named classification/watchdog time bounds; present-tense account limitation comment. Exactly-once completion, dry-run enforcement and body requests unchanged. |
| `Resources/SpamWiseRule.applescript` | Reviewed unchanged: Mail rule only opens the account-scoped app trigger; no message content in URL. |
| `Scripts/app-store-check.sh` | Assessed: validated token/mode, local signing checks and isolated archive path; shellcheck passes; not executed. |
| `Scripts/archive.sh` | Assessed: strict pipeline, explicit signed/unsigned modes and isolated archive output; shellcheck passes; Developer ID archive/export and signature verification pass. Notarization not repeated. |
| `Scripts/check.sh` | Assessed: strict shell, isolated worker paths and warning failure gate; shellcheck passes. |
| `Scripts/help-index.sh` | Assessed: quoted paths and language derivation; shellcheck passes; all three Help indexes rebuilt. |
| `Scripts/notarize-match.py` | Assessed read-only: narrow environment parsing, sanitized subprocess failures and private temporary key lifecycle. No Python change or credential operation warranted. |
| `Scripts/store-check.sh` | Assessed: isolated store fixture, cleanup trap and concurrent child waits; shellcheck passes. |
| `Scripts/store-probe.swift` | Named increment/deadline/retry bounds; existing process probe contract retained. |
| `Scripts/swiftdata-probe.swift` | Applied swift format. Fixed 50-row workload is development fixture input; positional argument contract and probe schema retained. |
| `Scripts/ui-check.sh` | Assessed: explicit UI lock and isolated worker build paths; shellcheck passes; both major UI flows pass. |
| `SpamWise/AccountSettingsView.swift` | Provider and selected transport grouped together; hides irrelevant connection forms. |
| `SpamWise/AdvancedSettingsView.swift` | Context, learning, optional evidence and integration diagnostics use disclosure controls. |
| `SpamWise/AppModel.swift` | Named polling/refresh/scan bounds; same-file functionality extensions preserve private access. Scan orchestrates named preparation, adapter discovery and classification helpers. Added explicit denied-permission state for accessible UI status. Numeric display uses FormatStyle. |
| `SpamWise/AppModelCredentials.swift` | Named verification budget/message constants. Credential flow delegates provider verification and durable record creation; credential handling order and state behavior preserved. |
| `SpamWise/AppModelErrors.swift` | New error presentation cluster composes LocalizedError description, failure reason and recovery suggestion, retaining actionable permission/Keychain advice and cancellation handling. |
| `SpamWise/AppModelIMAP.swift` | Consolidated required saved-connection loading with unchanged missing-configuration error; existing correction adapter and async execution remain intact. |
| `SpamWise/AppModelNavigation.swift` | App URL routing and Finder navigation are grouped in a small presentation extension. |
| `SpamWise/AppModelRules.swift` | Named the rule-import byte bound, preserving the extra sentinel byte and security-scoped resource lifetime. |
| `SpamWise/AppModelSettings.swift` | Existing provider-key save and typed bindings are small and coherent; formatting applied without semantic edits. |
| `SpamWise/ContentView.swift` | Native Activity toolbar, four essential columns, optional inspector and concise status footer; empty and paused modes. |
| `SpamWise/DecisionDetailView.swift` | Grouped details and correction controls; diagnostics disclosed on demand; Measurement latency and native numeric formats. |
| `SpamWise/EvidenceSettingsView.swift` | Conditional reputation configuration; required acknowledgement and unknown-on-failure explanation retained. |
| `SpamWise/GeneralSettingsView.swift` | Filtering and digest controls; dry-run validation gate retained; setup opens in the current Settings window. |
| `SpamWise/HelpButton.swift` | Native help-bezel NSButton with accessible label and narrow AppKit coordinator. |
| `SpamWise/IMAPConnectionModel.swift` | Extracted form normalization, connection persistence and credential handling into private actor-isolated helpers; reused connection loader; all Task entry points and state snapshots remain in place. |
| `SpamWise/IMAPSettingsView.swift` | Form-only view backed by observable connection model; advanced options disclosed; transport disabled during work. |
| `SpamWise/KeyEntryView.swift` | Secure entry, explicit verification cost context and conditional result feedback. |
| `SpamWise/LearningSettingsView.swift` | Learning and evaluation settings separated; populated domain suggestions preview. |
| `SpamWise/LocalizedLabels.swift` | Reviewed unchanged: explicit enum-to-localized-title presentation boundaries. |
| `SpamWise/MailConnectionView.swift` | Permission status and denied state; history, Contacts and action validation progressively disclosed. |
| `SpamWise/ModelSettingsView.swift` | Explicit provider selection and conditional credentials; usage details disclosed; previews for every backend. |
| `SpamWise/MyApp.swift` | Native Activity window group, standard Settings scene and Help menu; shared observable model. |
| `SpamWise/OnboardingView.swift` | Four typed steps with consistent navigation and grouped forms; concise privacy and optional offline setup. |
| `SpamWise/PolicyView.swift` | Dedicated preference editor with normalized default presentation, character budget and explicit Save/Reset. |
| `SpamWise/PreviewHelper.swift` | Injected isolated models cover empty, paused, failed action, provider, transport and suggestion modes. |
| `SpamWise/ReviewDigestView.swift` | Native list and explicit empty state in a dismissible sheet. |
| `SpamWise/RuleEditorView.swift` | Native table, selection actions, transfer menu and separate add/edit sheet. |
| `SpamWise/RuleFormView.swift` | Validated address/domain entry; existing identity fixed; failed saves retain draft and show error. |
| `SpamWise/RulesDocument.swift` | Thin FileDocument adapter validates regular-file data and uses a sorted pretty JSON encoder; formatting applied without semantic edits. |
| `SpamWise/SettingsView.swift` | Five native panes with remembered selection; test preferences isolated from production. |
| `SpamWise/SpamWise.help/Contents/Resources/en.lproj/correcting-mistakes.html` | Reviewed semantic Help navigation, responsive shared stylesheet and local links; Rules navigation updated in correction help. |
| `SpamWise/SpamWise.help/Contents/Resources/en.lproj/filtering-strength.html` | Reviewed semantic Help navigation, responsive shared stylesheet and local links; no change required. |
| `SpamWise/SpamWise.help/Contents/Resources/en.lproj/getting-started.html` | Reviewed semantic Help navigation, responsive shared stylesheet and local links; no change required. |
| `SpamWise/SpamWise.help/Contents/Resources/en.lproj/help.css` | Reviewed unchanged: system font, semantic system colors and narrow-window stacked navigation. |
| `SpamWise/SpamWise.help/Contents/Resources/en.lproj/how-decisions-are-made.html` | Reviewed semantic Help navigation, responsive shared stylesheet and local links; no change required. |
| `SpamWise/SpamWise.help/Contents/Resources/en.lproj/index.html` | Reviewed semantic Help navigation, responsive shared stylesheet and local links; no change required. |
| `SpamWise/SpamWise.help/Contents/Resources/en.lproj/troubleshooting-mail-integration.html` | Reviewed semantic Help navigation, responsive shared stylesheet and local links; no change required. |
| `SpamWise/SpamWise.help/Contents/Resources/en.lproj/what-data-is-sent.html` | Reviewed semantic Help navigation, responsive shared stylesheet and local links; no change required. |
| `SpamWise/SpamWise.help/Contents/Resources/es.lproj/correcting-mistakes.html` | Reviewed semantic Help navigation, responsive shared stylesheet and local links; Rules navigation updated in correction help. |
| `SpamWise/SpamWise.help/Contents/Resources/es.lproj/filtering-strength.html` | Reviewed semantic Help navigation, responsive shared stylesheet and local links; no change required. |
| `SpamWise/SpamWise.help/Contents/Resources/es.lproj/getting-started.html` | Reviewed semantic Help navigation, responsive shared stylesheet and local links; no change required. |
| `SpamWise/SpamWise.help/Contents/Resources/es.lproj/help.css` | Reviewed unchanged: system font, semantic system colors and narrow-window stacked navigation. |
| `SpamWise/SpamWise.help/Contents/Resources/es.lproj/how-decisions-are-made.html` | Reviewed semantic Help navigation, responsive shared stylesheet and local links; no change required. |
| `SpamWise/SpamWise.help/Contents/Resources/es.lproj/index.html` | Reviewed semantic Help navigation, responsive shared stylesheet and local links; no change required. |
| `SpamWise/SpamWise.help/Contents/Resources/es.lproj/troubleshooting-mail-integration.html` | Reviewed semantic Help navigation, responsive shared stylesheet and local links; no change required. |
| `SpamWise/SpamWise.help/Contents/Resources/es.lproj/what-data-is-sent.html` | Reviewed semantic Help navigation, responsive shared stylesheet and local links; no change required. |
| `SpamWise/SpamWise.help/Contents/Resources/fr.lproj/correcting-mistakes.html` | Reviewed semantic Help navigation, responsive shared stylesheet and local links; Rules navigation updated in correction help. |
| `SpamWise/SpamWise.help/Contents/Resources/fr.lproj/filtering-strength.html` | Reviewed semantic Help navigation, responsive shared stylesheet and local links; no change required. |
| `SpamWise/SpamWise.help/Contents/Resources/fr.lproj/getting-started.html` | Reviewed semantic Help navigation, responsive shared stylesheet and local links; no change required. |
| `SpamWise/SpamWise.help/Contents/Resources/fr.lproj/help.css` | Reviewed unchanged: system font, semantic system colors and narrow-window stacked navigation. |
| `SpamWise/SpamWise.help/Contents/Resources/fr.lproj/how-decisions-are-made.html` | Reviewed semantic Help navigation, responsive shared stylesheet and local links; no change required. |
| `SpamWise/SpamWise.help/Contents/Resources/fr.lproj/index.html` | Reviewed semantic Help navigation, responsive shared stylesheet and local links; no change required. |
| `SpamWise/SpamWise.help/Contents/Resources/fr.lproj/troubleshooting-mail-integration.html` | Reviewed semantic Help navigation, responsive shared stylesheet and local links; no change required. |
| `SpamWise/SpamWise.help/Contents/Resources/fr.lproj/what-data-is-sent.html` | Reviewed semantic Help navigation, responsive shared stylesheet and local links; no change required. |
| `SpamWise/UITestFixture.swift` | DEBUG-only synthetic seeds and denied Apple Events boundary; deterministic correction and visual fixtures. |
| `SpamWiseCore/Package.swift` | Formatted manifest; macOS 27 and Swift 6.4 app/tool package; one shared upcoming-feature and memory-safety configuration for all targets. |
| `SpamWiseCore/Sources/Classifier/AppleClassifier.swift` | Named generation/deadline bounds, type-method ordering, public case DocC. |
| `SpamWiseCore/Sources/Classifier/ClassificationLimits.swift` | Added internal shared bounds for provider requests and prompt construction. |
| `SpamWiseCore/Sources/Classifier/ClaudeClassifier.swift` | Moved credential property before initializers; named response-token bound. |
| `SpamWiseCore/Sources/Classifier/Deadline.swift` | Assessed; documented typed boundary already delegates timeout/cancellation management. No change needed. |
| `SpamWiseCore/Sources/Classifier/GeminiClassifier.swift` | Named response and usage bounds; preserves provider response decoding and rejection semantics. |
| `SpamWiseCore/Sources/Classifier/ModelHTTPClient.swift` | Reused named transport deadline; response/status types and injected boundary already documented. |
| `SpamWiseCore/Sources/Classifier/ModelTokenPricing.swift` | Named pricing transition date/multiplier and corrected declaration order; captured rate data unchanged. |
| `SpamWiseCore/Sources/Classifier/OpenAIClassifier.swift` | Named response-token bound; explicit wire fields remain stable. |
| `SpamWiseCore/Sources/Classifier/RemoteVerdict.swift` | Named byte/count/deadline bounds, bounded-time helper, declaration order. |
| `SpamWiseCore/Sources/Classifier/Types.swift` | Error category protocol and localized category/detail, public member DocC, named bounds; prompt helper orchestration preserves escaping and generated text. |
| `SpamWiseCore/Sources/Decision/Decision.swift` | Public case DocC; policy already uses domain enums and pure evaluation. Threshold data remains unchanged. |
| `SpamWiseCore/Sources/Evaluation/CachedClassifier.swift` | Assessed: actor state, public docs and small cache orchestration comply. POSIX permissions 0700/0600 are intentional standard notation; cache identity and disk format unchanged. |
| `SpamWiseCore/Sources/Evaluation/Metrics.swift` | Named binomial tail and iteration constants. Metric fields retain signed Int public Codable contracts; 0/1 probability arithmetic and decile bucket arithmetic are mathematical notation. |
| `SpamWiseCore/Sources/Evaluation/ReviewedCorpus.swift` | Added corpus error category with localized description/reason/actionable recovery; named input limits; retained public export bound and Codable partition format. |
| `SpamWiseCore/Sources/Learning/CampaignLearning.swift` | Named fingerprint, lexical, and anchor bounds; shingle arithmetic preserves five-word windows. |
| `SpamWiseCore/Sources/Learning/CorrectionLearning.swift` | Named retrieval/distillation/tokenization bounds; typed scored correction replaces positional tuples. |
| `SpamWiseCore/Sources/Learning/LearningState.swift` | Named retention, partition, confidence, and admission constraints; initializer order and public case DocC. |
| `SpamWiseCore/Sources/Learning/StatisticalLearning.swift` | Named evidence saturation, class-support, prediction-weight, and training bounds; formulas unchanged. |
| `SpamWiseCore/Sources/MailIntegration/AppleMailAdapter.swift` | Documented public runner requirement and MailAccount fields; documented owned serial executor confinement; named scan/message bounds; ordered envelope decoder before instance methods. Apple Event error numbers and envelope positions remain protocol constants. |
| `SpamWiseCore/Sources/MailIntegration/IMAPAdapter.swift` | Named history/message bounds. Existing session orchestration, dedicated helper extension, exact UID verification and public Int identity contract retained. |
| `SpamWiseCore/Sources/MailIntegration/IMAPConfiguration.swift` | Named endpoint/identity bounds. UInt16 port and strict decoding retained; standard TLS port 993 and ASCII host grammar remain direct protocol values. |
| `SpamWiseCore/Sources/MailIntegration/IMAPDaemonConfiguration.swift` | Named configuration, secret-reference and path bounds. Keychain interaction remains explicitly noninteractive and narrow unsafe SecItemCopyMatching. |
| `SpamWiseCore/Sources/MailIntegration/IMAPPaging.swift` | Named page and aggregate byte bounds; stable paging/offset behavior retained; private metadata remains an internal transport value. |
| `SpamWiseCore/Sources/MailIntegration/IMAPProtocol.swift` | Named response, literal, token, nesting, command and quote bounds; ordered static parsing helpers. ASCII token bytes and protocol tuple indices remain direct grammar notation. |
| `SpamWiseCore/Sources/MailIntegration/IMAPSweepCursor.swift` | Assessed: small value type with explicit validity reset; no warranted rewrite. |
| `SpamWiseCore/Sources/MailIntegration/IMAPTransport.swift` | Added IMAP error category and localized details without server content; named chunk/session limits; grouped imports. Network.framework callback completion remains Mutex guarded. |
| `SpamWiseCore/Sources/MailIntegration/MailScripts.swift` | Named page bound and ordered script constants before builders. Eight-second AppleScript timeout, error codes and orange flag index are preserved script-language protocol literals; no generated Mail action changed. |
| `SpamWiseCore/Sources/MessageModel/DomainResolver.swift` | Named DNS label bound; C inet_pton remains a narrow checked interop expression; bundled PSL is unchanged. |
| `SpamWiseCore/Sources/MessageModel/EmbeddedImageOCR.swift` | Named OCR deadline and content limits; extracted bounded recognition helper; ordered static and instance methods. |
| `SpamWiseCore/Sources/MessageModel/EmbeddedImages.swift` | Named MIME, aggregate-image and image-dimension bounds; ordered pixel validation helper before instance methods. |
| `SpamWiseCore/Sources/MessageModel/Identity.swift` | Moved computed identity key before initializer; existing Int identifiers and Codable keys retained for store compatibility. |
| `SpamWiseCore/Sources/MessageModel/MIMEParser.swift` | Named byte, nesting, part, URL and text bounds; descriptive charset and part names; ordered helper cluster and nested Content type. ASCII bytes, hex radix and base64 arithmetic remain protocol notation. |
| `SpamWiseCore/Sources/MessageModel/Message.swift` | Added parsing error category and localized category/reasons. Existing urls key retained for persisted and prompt Codable compatibility. |
| `SpamWiseCore/Sources/MessageModel/ResourceDeadline.swift` | Added deadline error category and localization; named minimum timeout; moved nested state to end. Mutex-based exactly-once detached race is intentional to avoid awaiting uncooperative work. |
| `SpamWiseCore/Sources/Signals/Evidence.swift` | Named header/domain evidence caps; actor and Sendable value confinement retained. Authentication claim tokens and serialized field names remain byte-stable prompt evidence. |
| `SpamWiseCore/Sources/Signals/EvidenceProcess.swift` | Added local-evidence error category/details and named process byte/deadline/poll bounds. Foundation Process and pipes stay inside the execution boundary; SIGKILL cancellation and F_SETNOSIGPIPE remain explicit interop. |
| `SpamWiseCore/Sources/Signals/ExternalEvidence.swift` | Named query, observation, domain and answer bounds; ordered members. DNS wire values, ASCII grammar and prompt summary remain unlocalized by design. |
| `SpamWiseCore/Sources/Signals/Gates.swift` | Ordered history computed property before initializer. Rule precedence, evidence sentences and persisted counters retain existing semantics and encoding. |
| `SpamWiseCore/Sources/Signals/RDAP.swift` | Documented fetch protocol requirement; named timeout/cache/byte bounds; extracted registration-date helper and moved response types to end. |
| `SpamWiseCore/Sources/Signals/RspamdLookup.swift` | Named byte/symbol/score/detail limits with explicit Double score type. Protocol endpoint, timeout argument and uppercase ASCII symbol grammar remain literal wire syntax. |
| `SpamWiseCore/Sources/SpamWiseCore/AdvancedSettings.swift` | Public case DocC and named digest lookback; persisted keys/defaults unchanged. |
| `SpamWiseCore/Sources/SpamWiseCore/CompletionOnce.swift` | Correct multiline DocC; reviewed lock ownership and legacy callback exception. |
| `SpamWiseCore/Sources/SpamWiseCore/ConfiguredClassifier.swift` | Named model spending reservation amounts; explicit provider selection unchanged. |
| `SpamWiseCore/Sources/SpamWiseCore/EvaluationBudget.swift` | Budget error category protocol and localized category/detail; error-case DocC. |
| `SpamWiseCore/Sources/SpamWiseCore/Exports.swift` | Assessed; compatibility reexports only, no runtime code or undocumented declarations. No change needed. |
| `SpamWiseCore/Sources/SpamWiseCore/MailClientAdapter.swift` | Protocol requirement DocC; mail error category and localized category/detail plus case DocC. |
| `SpamWiseCore/Sources/SpamWiseCore/Pipeline.swift` | Named retry bounds and backoff values; preserves localized failure detail when recording integration errors. |
| `SpamWiseCore/Sources/SpamWiseCore/PipelineClassification.swift` | Named evidence/deadline constraints; nested type moved after methods. |
| `SpamWiseCore/Sources/SpamWiseCore/PipelineCorrections.swift` | Named retention bounds, descriptive index name, type-method order. |
| `SpamWiseCore/Sources/SpamWiseCore/RuleManagement.swift` | Error category and localized category/detail; named archive/rule bounds; declaration order and error-case DocC. |
| `SpamWiseCore/Sources/SpamWiseCore/State.swift` | Named retention/settings bounds, type-method order, incoming-route case DocC. |
| `SpamWiseCore/Sources/SpamWiseDaemon/main.swift` | Named configuration read bound and permitted polling/page ranges. Existing explicit CLI syntax and operational transcript retained; no provider, credential or Mail operations executed. |
| `SpamWiseCore/Sources/SpamWiseEval/Options.swift` | Ordered computed properties before initializer; evaluation errors share corpus category and use localized diagnostics. Usage documents exact command grammar and remains source-English. |
| `SpamWiseCore/Sources/SpamWiseEval/RunReport.swift` | Named calibration sample target and explicitly Double tokens-per-million denominator. JSON keys and explanatory report text remain stable output data. |
| `SpamWiseCore/Sources/SpamWiseEval/main.swift` | Named MIME input bound; joined sanitized localized category/details/recovery for diagnostic display. Provider selection, budget bounds, corpus ordering and report data remain unchanged. |
| `SpamWiseCore/Sources/Store/Keychain.swift` | Credential error category and localized category/detail; declaration order and error-case DocC. Narrow Security unsafe annotation preserved. |
| `SpamWiseCore/Sources/Store/Store.swift` | Storage error category and localized category/detail; multiline DocC style and case documentation. Actor transaction and process lock unchanged. |
| `SpamWiseCore/Tests/SpamWiseCoreTests/ClassifierTests.swift` | Raw verb names for all cases, typed throwing assertions, preserved opt-in live gate. |
| `SpamWiseCore/Tests/SpamWiseCoreTests/DecisionTests.swift` | Raw verb names aligned with asserted behavior. Existing store, envelope and adapter helpers retained. |
| `SpamWiseCore/Tests/SpamWiseCoreTests/EmbeddedImageTests.swift` | Raw verb names; bounded inline-image fixture helper retained. |
| `SpamWiseCore/Tests/SpamWiseCoreTests/EvaluationTests.swift` | Raw verb names; #require replaces forced unwraps on optional binomial bounds. |
| `SpamWiseCore/Tests/SpamWiseCoreTests/ExternalEvidenceTests.swift` | Raw verb names; injected DNS and process assertions retained as project-boundary behavior. |
| `SpamWiseCore/Tests/SpamWiseCoreTests/IMAPFixtureTransport.swift` | Reviewed unchanged: actor-backed fixture transport is Sendable, bounded and used. |
| `SpamWiseCore/Tests/SpamWiseCoreTests/IMAPTests.swift` | Raw suite name and canonical static-property/method ordering; transcript helpers retained. |
| `SpamWiseCore/Tests/SpamWiseCoreTests/LearningTests.swift` | Raw suite name. Enriched inference helper returns a named fixture; assertions now remain in the test body. |
| `SpamWiseCore/Tests/SpamWiseCoreTests/MailIntegrationTests.swift` | Raw verb names, typed stale-source assertion and imports grouped at file start. |
| `SpamWiseCore/Tests/SpamWiseCoreTests/ParsingTests.swift` | Raw verb name replaces camelCase; MIME acronym and descriptive verb naming corrected. |
| `SpamWiseCore/Tests/SpamWiseCoreTests/ProviderTests.swift` | Raw verb names with correct OpenAI capitalization; provider response fixtures retained. |
| `SpamWiseCore/Tests/SpamWiseCoreTests/RoadmapStateTests.swift` | Raw verb names; meaningful state migration, rule transaction and concurrent budget behavior retained. |
| `SpamWiseCore/Tests/SpamWiseCoreTests/SignalsTests.swift` | Raw verb names; #require replaces forced date unwrap and rollback explicitly expects the typed error. |
| `UITests/UITests.swift` | XCTest retained. Typed onboarding step transitions and screen landing waits; Cmd-comma opens Rules; semantic identifiers/values replace localized status queries. Two existing major flows preserved. |
| `UnitTests/UnitTests.swift` | Reviewed unchanged: import-only Xcode unit target; no placeholder or tautological test added. |

## Verification

- `Scripts/check.sh ca664761-7b58-458e-9bda-cd338002266a`: all 72 package
  tests pass; app and extension build with warnings treated as errors. The opt-in
  live API test is skipped.
- Strict SwiftLint, `swift format lint --strict`, shellcheck, yamllint, Markdown
  lint, project/plist validation and `git diff --check` pass.
- The production Store probe verifies 100 atomic increments from two processes.
  Offline evaluation gives two Inbox, two Junk and one Review with no fixture
  mismatches; the cached rerun has five hits and zero new model usage.
- All 420 catalog entries have Spanish and French translations with matching
  format placeholders. All extracted interface keys are covered. Help links and
  anchors validate, and all three Help indexes are rebuilt.
- Developer ID archive/export and deep strict signature verification pass. Bundle
  identifiers, signing team, App Group and Keychain entitlements are preserved.
  This review does not repeat notarization or install the rewritten app.

Native inspection covers all 27 view/representable types, the five providers,
both connection forms, rule add/edit sheets, learning suggestions, optional evidence,
diagnostics, populated/empty digest, offline setup and denied-permission states.
English, Spanish and French layouts were inspected. Activity/setup were exercised
at 720 pixels wide; native Settings retained an 800 × 628 window despite attempts
to resize it smaller, so a smaller Settings window is not claimed as verified.

The inspection reproduced two real overlaps: long Settings status text underneath
the Accounts form, and Activity diagnostics underneath its footer at narrow size.
Separating each footer from scrollable content fixes both. Native toolbar behavior
is preserved. Help buttons and nested form controls were aligned consistently.
Evidence: `.build/3fd3b409-633f-494a-8220-afc7729009b6/ui-visual/`, including
`fr-accounts-denied-bottom.jpg` and `final-evidence-bottom.jpg`.

Final XCTest run: both flows pass with zero failures in 71.713 seconds. The
correction flow covers Good/Junk/Review, address replacement, explicit domain rules,
rule add/edit and retained corrections after Mail-action failure. The setup flow
covers all four offline steps, simulated denied permission, dry run and Pause.
Result: `.build/ca664761-7b58-458e-9bda-cd338002266a/DerivedData/Logs/Test/Test-SpamWise-2026.10.16_12-03-01--0700.xcresult`.
General’s setup sheet also completed all four French steps and returned to General
in native inspection (`final-setup-sheet-completed.jpg`).
No paid API requests or real-mail actions were made during this review.
