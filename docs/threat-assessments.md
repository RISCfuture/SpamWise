# Independent threat assessments

Spam, phishing, spearphishing, fraud and malware findings are separate from
Inbox/Review/Junk preferences and Mail actions. An unwanted newsletter is not a
verified phishing label. An Inbox decision, contact match or earlier reply is not
a security scan.

## Pipeline and persistence

The pipeline accepts an optional `ThreatDetector`. It assesses all successful
classification paths, including address/domain rules, trusted contacts/history
and campaign gates. Explicit rules still determine the action; findings cannot
request moves. Paused, failed and historical records have no completed assessment.
Corrections retain the original assessment without converting action labels into
threat-training labels.

No production detector is selected, so app records carry no assessment, which means
unknown for every objective. The injection interface and synthetic tests establish
orchestration, not predictive quality. Candidate selection and calibration are
tracked in [TODO.md](../TODO.md).

Input includes the parsed message, account identity and available relationship
and authentication evidence. Preference-derived Bayes and learned-margin scores
are removed. Missing history remains unavailable. Policy text and correction
examples are not supplied to independent detectors. Detector implementations must
treat content as untrusted and state their language, truncation and attachment
coverage. A text model must not certify attachments as safe.

A finding contains an objective, detected/not-detected/unknown state, short reason,
coverage and optional uncalibrated score. Unknown has no score. Duplicate
objectives, nonfinite/out-of-range scores, missing explanations and missing
detector identities are rejected. Unsupported objectives become unknown.

Persisted provenance includes detector implementation, model, preprocessing and
policy revisions, plus a hash of effective content, account and evidence. Optional
analysis gets at most two seconds and one quarter of the remaining pipeline
budget. Detector errors and deadline expiry produce unknown findings; cancellation
still stops the pipeline. Persistence, revision checks and action claims retain
their existing fail-open behavior. Local mode rejects network detectors before
calling them. Implementations remain responsible for bounded resource use and
truthful network declarations.

## Cache and evaluation

`CachedThreatDetector` uses effective content (including extracted text), account,
evidence, complete detector configuration and assessment schema in its key.
Cached responses are revalidated. Wholly unknown responses are not cached;
partially supported results retain unknown objectives when reused. A newly
supported objective requires a detector identity revision. This cache is separate
from the preference classifier cache and never replays a Mail action.

The evaluator accepts independent objective observations without making provider
calls or accessing Mail:

```sh
swift run --package-path SpamWiseCore --scratch-path .build/swiftpm \
  spamwise-eval threat-report observations.json --output report.json
```

The input is a JSON array. Each row contains a unique `sampleID`, `language`,
explicit objective `truth` labels and an optional persisted `assessment` object.
For example, an unassessed difficult legitimate message can be represented as:

```json
[
  {
    "sampleID": "independently-reviewed-example",
    "language": "en",
    "truth": { "spam": false },
    "assessment": null
  }
]
```

Omitted objectives have unknown truth. Do not infer phishing negatives from a
non-spam source, or positives from Junk membership. Reports separate objective and
language counts, unlabeled samples, unassessed samples, precision and recall.
Unassessed positives count as missed detections. The false-positive bound uses
only negative samples that were actually assessed, so missing coverage cannot
make the bound look better. Duplicate sample identities and invalid findings are
rejected. Source/campaign deduplication, independent truth review and exposure
control remain corpus preparation responsibilities.

Synthetic tests cover trusted-contact and explicit-rule paths, persistence,
historical decoding, local-mode exclusion, failed/invalid detector outputs,
account/evidence/policy/content cache invalidation and independent metric
semantics. These tests do not establish a universal detector, calibrated scores,
spearphishing quality, attachment safety or actual model fine-tuning.
