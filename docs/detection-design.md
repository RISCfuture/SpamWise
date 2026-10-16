# Separate threat detection from mail preferences

Product direction confirmed 2026-10-16. This is the target design, not a claim that
the current Inbox/Review/Junk classifier implements independent detectors.

SpamWise should work from installation using pretrained general detectors and
zero-shot preference interpretation. A personal mailbox receiving roughly twenty
messages per day is useful for incremental personalization, not a prerequisite
for training a universal model. Public training data and private preferences
serve different purposes. See the [dataset assessment](training-data.md).

## Detection vocabulary

These findings can overlap; do not force every message into one exclusive class.

| Finding | Meaning in SpamWise | Training and evidence |
| --- | --- | --- |
| Spam | Unsolicited bulk abuse, independent of an individual newsletter preference | Separately labeled bulk-spam and legitimate-mail corpora; campaign-disjoint evaluation; local pretrained baseline |
| Graymail | Legitimate bulk, promotional or notification mail whose usefulness depends on the recipient | Zero-shot user policy, explicit corrections and bounded retrieval; private personalization rather than universal unwanted labels |
| Phishing | Deceptive attempts to obtain credentials, sensitive information, money or harmful interaction | Dedicated phishing examples and difficult legitimate counterparts; sender/brand/link relationships and requested actions |
| Spearphishing | Targeted phishing using recipient or relationship context | General threat evidence plus account-scoped correspondence context, impersonation and unusual requests; evaluate with and without history |
| Fraud or scam | Deceptive payment, refund, investment, extortion or other schemes, including messages without credential links | Separate scam examples and legitimate financial requests; BEC/payment diversion can overlap spearphishing |
| Malware delivery | Attempts to deliver or induce execution of malicious content | Dedicated attachment/link evidence and format-specific analysis; a text classifier cannot certify an attachment safe |

Spearphishing is a targeted form of phishing, not a mutually exclusive alternative.
[CISA's description](https://www.cisa.gov/sites/default/files/2024-02/Update%20to%20Phishing%20General%20Security%20Postcard_01.01.2024.pdf)
supports keeping targeting as an additional finding. BEC can originate from a
compromised legitimate account; correspondence and authentication alone cannot
establish safety. See the [IC3 description](https://www.ic3.gov/CrimeInfo/BEC).

Keep wanted personal, transactional, security and subscription mail represented in
negative examples. Unknown is an assessment state, not another threat category.
QR codes, calendar invitations, attachment lures and thread hijacking describe
delivery techniques; store them as supporting evidence instead of adding a large
set of competing top-level categories. Prompt injection is a classifier-integrity
concern, not automatic proof that the surrounding email is spam.

## Model and action boundaries

- Separate general spam and phishing objectives, labels, calibration and metrics.
  They may share a compact encoder if measurement supports it; separate tasks do
  not require downloading one large model per category.
- Keep each finding's detector/version, evidence, coverage and score provenance.
  Missing context, unsupported language, parsing failure and unavailable detectors
  remain unknown. Raw neural scores and LLM confidence are not calibrated odds.
- Retain an independent personal preference result. Marking a newsletter unwanted
  must not teach the general phishing detector that the sender is malicious.
  Correcting an action alone does not supply a verified threat label.
- Keep existing address/domain rule precedence and separate model verdict,
  intended action and action outcome. Do not silently turn threat findings into
  new moves or override explicit rules. Preserve no Trash/delete and fail-open.
- Trusted-contact/history gates currently skip classification. Independent threat
  coverage requires a separate assessment path even for trusted mail, while
  leaving the existing rule-driven action intact. A gate-approved Inbox result
  must never be presented as a completed security scan.
- Unknown targeting history cannot prove or disprove spearphishing. Unusual style,
  urgency or a new bank account is supporting evidence, not a decisive rule.
- Start graymail personalization with policy and reviewed-example retrieval.
  These are already supported techniques, but are not weight fine-tuning. Actual
  local adapter/weight training needs its own data sufficiency, rollback and
  held-out evaluation checks; no shared upload of personal corrections is implied.

The UI should show a short primary explanation and only relevant findings, with
details in the inspector. Inbox/Review/Junk remain destinations; they are not the
training taxonomy. A legitimate newsletter can be unwanted, and an allowed sender
can still merit a threat finding.

## Evaluation and implementation sequence

1. Audit candidate models and public datasets for provenance, label meaning,
   redistribution rights, language coverage, size and overlap with evaluation data.
2. Add backward-compatible independent assessments to records and evaluation.
   Historical records are unassessed, never implicitly safe. Include assessment,
   tokenizer, model, prompt and schema identities in cache keys.
3. Benchmark local general-spam and phishing candidates independently. Compare
   source/campaign/time-separated real data and synthetic challenge sets; report
   them separately. Do not relabel all spam as phishing to increase sample count.
4. Integrate the selected local runtime with bounded resource use, cancellation,
   offline operation and explicit unsupported states. Test the separate trusted
   mail assessment path and preserve persistence-before-action.
5. Evaluate zero-shot preferences and small incremental personal corrections.
   Measure preference usefulness separately from threat recall and false alarms.
6. Evaluate targeting and fraud with legitimate invoices, password resets,
   document shares and real correspondence patterns as difficult negatives.
   Review attachment coverage separately; no antivirus-equivalence claim.

Report precision/recall, abstention, false positives, latency and resource use per
finding and language, plus preference agreement and final-action errors. Do not
use a tiny personal corpus to claim universal accuracy. The approximately 1,500
independent good examples required for a zero-error 0.2% rule-of-three upper bound
are an accuracy-claim criterion, not a requirement to begin useful personalization.

## Implemented assessment boundary

The independent persistence, bounded detector interface, trusted-mail assessment
path, coverage inspector, detector cache and objective-report CLI are implemented.
See [threat assessment behavior](threat-assessments.md). No production detector is
selected: the app explicitly reports unassessed coverage until model quality and
runtime integration are established. This does not replace the remaining model,
calibration, targeting or personalization evaluation steps above.
