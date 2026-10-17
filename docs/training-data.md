# Public email training data

Investigated 2026-10-16 for the [separate detection tasks](detection-design.md).
Use public corpora for general models and keep personal graymail preferences
private. A new upload date is not evidence of recent message collection.

## Recommended starting sources

| Source | Size and freshness | Published terms | Use in SpamWise |
| --- | --- | --- | --- |
| [Bruce Guenter spam archive](https://untroubled.org/spam/) | Annual archives plus monthly 2026 files through October; September download contains 1,476 non-directory entries | Author explicitly grants unrestricted use; attribution appreciated | Recent bulk spam, with campaign deduplication and a separate phishing/scam relabeling pass. No legitimate negatives; trap/mailbox sampling bias |
| [José Nazario phishing corpus](https://monkey.org/~jose/phishing/) | Annual mailboxes through 2025; downloaded 2025 file contains 481 messages | [CC BY 4.0, explicitly allowing derivatives and commercial use](https://monkey.org/~jose/phishing/README.txt) | Recent real phishing with MIME/headers. Hand labels may contain errors; one inbox and no legitimate negatives. Later mailboxes are not anonymized |
| [Marketeam Marketing-Emails](https://huggingface.co/datasets/marketeam/Marketing-Emails) | 16,440 synthetic messages; repository created November 2025, generation dates unspecified | Dataset card declares MIT | Legitimate marketing/workplace language and preference challenge material. CSV has text only, no wanted/unwanted or verified threat labels; never label the whole corpus unwanted |
| [MeAJOR v2](https://zenodo.org/records/18471483) | 108,685 records, February 2026 release; combines TREC-05/06/07, Nazario and Nigerian Fraud | Zenodo API declares CC BY 4.0; constituent provenance still needs review | Bulk historical baseline with source field. Preserve source labels and review the spam-to-phishing mapping before training separate objectives; anonymization removes some identity evidence |

Guenter's source warns that forged headers are common and that a major collection
domain expired in 2018. Keep those coverage limitations in the model card, even
when using recent files. Its current-month archive changes; pin a downloaded hash
and avoid repeatedly fetching the same file.

## Supplemental or unsuitable sources

| Source | What it actually offers | Disposition |
| --- | --- | --- |
| [NEST-Phish](https://arxiv.org/html/2609.04474v1), [dataset](https://www.kaggle.com/datasets/emilywinokur/synthetic-email-corpus) | September 2026 paper; 146 retained synthetic emails, 77 legitimate and 69 phishing, matched workplace scenarios and human evaluation | Useful difficult-case evaluation, not bulk training. Verify the dataset's own license; the paper's license does not establish it |
| [CIC-Trap4Phish](https://www.unb.ca/cic/datasets/trap4phish2025.html) | 20,000 samples each for Word, Excel, PDF and HTML, plus large QR/URL sets; 2026 paper | Attachment/QR-specific follow-up, not a complete-email corpus. Confirm dataset terms and handle samples without execution |
| [Merged nine-corpus dataset](https://github.com/Manar-ibr/Phishing-Email-Detection-Dataset), [download](https://zenodo.org/records/17314806) | October 2025 release of 1998–2008 mail; 391 MB merged CSV. Authors explicitly combine spam, scams and phishing as “phishing”; Zenodo API declares CC BY 4.0 | Historical baseline only after source/label audit. Do not teach our phishing detector this collapsed label |
| [Sting9](https://sting9.org/dataset) | Advertises updated message dumps, metadata and verification flags | Hold: data page says CC0, but the [license page](https://sting9.org/license) imposes noncommercial/product-development restrictions. Do not treat a free app as resolving those conflicting terms |
| [UniqueData generated spam](https://huggingface.co/datasets/UniqueData/generated-e-mail-spam) | 300 generated samples using text-davinci-003; commercial collection offered separately | Reject as the main free bulk source: small sample, CC BY-NC-ND 4.0, no evidence of recent generation |
| [PhishNChips](https://huggingface.co/datasets/AreLit/PhishNChips) | 2026 synthetic/real email-agent benchmark; project content MIT, mixed external indicators | Potential evaluation source; isolate components and their rights. [Source terms](https://github.com/R-Lit/PhishNChips_Neurips/blob/main/SOURCE_LICENSES.md) include academic-only permission |
| [Modern APWG study](https://arxiv.org/html/2609.30683v1) | 2.9 million distinct real phishing emails collected June 2025–June 2026 through an APWG partnership | Recent research, but no unrestricted bulk download was established in this audit. Do not count it as acquired training data |
| [SendGuard900K](https://zenodo.org/records/17985618) | Marketing campaign metadata collected 2022–2024, released December 2025 | Not a body-text training source; the release explicitly omits message content |

## Download verification

Downloaded only into ignored local artifacts under
`.build/9bdac1b8-1027-4502-a77b-e1a9b0abc471/corpus-audit/`. Nothing was
imported into Mail, rendered as HTML, executed as an attachment, uploaded to a
provider, or added to the public site. No API charges were incurred.

| File | Observed bytes | SHA-256 |
| --- | --- | --- |
| `guenter-2026-09.7z` | 2,009,979 | `0e2cd6d56012d66cfc621d2775c118ecbb29754c603f70ed05d763e90616ffda` |
| `nazario-2025.mbox` | 18,769,863 | `f1fa7e0fe35c9a16f36d9aa20ade7e1d3908d1d0c1d917b8c53c8aa799ec1c8f` |
| `marketing.csv` | 32,692,614 | `7945198268c8bcded668e6e0e684d36ee241c584bd6e5a4bd76a30359c296a30` |

The marketing download pins revision
`56377f4213c15921f724add23ab175b0a5a0eea1`; CSV parsing confirms 16,440 rows
and one column named `0`. It has no classification labels. Nazario's mailbox has
481 distinct serialized messages: 477 claim a 2025 Date, one claims 2024, and three
have missing/unparseable dates. Sender-controlled Date headers are not independent
proof of collection time. These counts do not establish campaign independence or
label correctness. Guenter's count is an archive listing, not a count of parsed,
deduplicated messages. Source/license snapshots and inventory JSON are alongside
the downloads.

## Acquisition and training policy

1. Start with Guenter for bulk spam, Nazario for phishing, and synthetic legitimate
   material for difficult negatives. Supplement with source-audited historical
   legitimate mail; recent representative legitimate mail remains a coverage gap.
2. Keep original source, revision/hash, license, collection-date evidence, language,
   original label, label authority and real/synthetic provenance on every record.
   Record labels not supplied by a source as unknown, not false.
3. Review mapping to spam, phishing, fraud, targeting and malware independently.
   Do not infer spearphishing merely from a salutation or infer maliciousness from
   Junk membership. User-specific wanted/unwanted labels remain a separate task.
4. Deduplicate across all sources and pretrained training corpora. Split by
   campaign/template and time before training, including all synthetic variants of
   one scenario in the same split. Reserve an untouched real-mail evaluation set.
5. Include legitimate security notices, invoices, receipts, document shares and
   desired newsletters. English coverage does not establish Spanish/French
   coverage; report those separately and retain unknown language states.
6. Use generated examples for controlled coverage gaps, not as a substitute for
   real-mail evaluation or as independent human labels. Do not claim a modern
   source is unseen by a pretrained model without evidence of its training cutoff.
7. Publish model attribution, source limitations and separate metrics. No monthly
   collection target for the user's personal mailbox blocks initial personalization.

## Reproducible local preparation

The [corpus tools](../Tools/Corpus/README.md) verify all three pinned hashes and
preserve source attribution and independent labels. The 2026-10-16 run processed
18,397 input records into 18,201 unique text records, merging 184 normalized-text
duplicates and quarantining 12 records: six encoding failures, five MIME defects
and one empty text body. Original downloads remain intact.

There are 17,735 heuristic template groups, including 157 groups with more than
one distinct record; the largest contains 24. Shared templates stay in one split
across sources. This detects some repeated campaigns; it is not proof of campaign
independence. The fixed seed is `spamwise-public-2026-10-v1`.

| Provenance | Training | Validation | Reserved holdout |
| --- | ---: | ---: | ---: |
| Real source-labeled spam | 936 | 181 | 202 |
| Real source-labeled phishing | 307 | 78 | 57 |
| Unlabeled synthetic | 11,545 | 2,372 | 2,523 |

The source-positive objectives have no independently verified legitimate
negatives. Missing labels, language and targeting remain unknown; synthetic text
is not relabeled as wanted mail. Conflicting duplicate labels abstain for that
objective. The partitions are provisional hash splits, not temporal holdouts;
campaign review and pretrained exposure checks remain necessary. Development
screening uses the real validation subset only, leaving reserved holdout records
out of model inference.

Prepared text and per-record results remain in ignored private output. Only
aggregate counts and source metadata belong in repository documentation. Full
commands, resource limits, output permissions and completion/hash checks are in
the tool README.

An additional check of the
[original SpamAssassin corpus terms](https://spamassassin.apache.org/old/publiccorpus/readme.html)
found an explicit invitation to test filters, with message copyright retained by
senders. Do not inherit a mirror's CC0 claim or the software's Apache license for
the emails. Its historical hard-ham examples may support an offline development
comparison; model-training/redistribution permission is not established here.

No model training or production model selection follows from these downloads.
Dataset sizes, source availability and published rights above were checked on the
audit date; verify the exact version again before redistribution.
