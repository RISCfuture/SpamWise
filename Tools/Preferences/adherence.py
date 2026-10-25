"""Measure whether SpamWise applies per-category preference profiles to a blind message set."""

import argparse
import hashlib
import html
import json
import math
import os
import random
import re
import signal
import subprocess
import sys
import tomllib
import unicodedata
import uuid
from collections import Counter, defaultdict
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from email import policy
from email.message import EmailMessage
from email.parser import BytesParser
from email.utils import format_datetime, getaddresses
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "Tools" / "Corpus"))
import prepare

SEED = "spamwise-adherence-2026-10-v1"
MESSAGES_SCHEMA = "spamwise-adherence-messages-v1"
LABELS_SCHEMA = "spamwise-adherence-labels-v1"
SCORE_SCHEMA = "spamwise-adherence-score-v1"
CATEGORIES = (
    "personal",
    "transactional",
    "community",
    "promotion",
    "abandonedCart",
    "newsletter",
    "productUpdate",
    "event",
    "socialNotification",
    "survey",
    "financialOffer",
    "fundraising",
    "coldOutreach",
    "spam",
    "scam",
)
GRAYMAIL = (
    "promotion",
    "abandonedCart",
    "newsletter",
    "productUpdate",
    "event",
    "socialNotification",
    "survey",
    "financialOffer",
    "fundraising",
    "coldOutreach",
    "community",
)
THREATS = ("spam", "scam")
PREFERENCE_ACTIONS = {"keep": "inbox", "review": "review", "junk": "junk"}
ACTIONS = ("inbox", "review", "junk", "unclassified")
SPLITS = ("dev", "holdout")
SWEEP_THRESHOLDS = tuple(range(50, 101, 5))
MARKETEAM = "marketeam-56377f4"
MARKETEAM_COUNT = 80
THREAT_COUNTS = {"nazario-2025": 5, "guenter-2026-09": 5}
MAX_THREAT_BYTES = 200_000
RESERVATION_USD = 0.008
LIVE_MODEL = "claude-haiku-5-5"
LAUNCHER = ROOT / "Scripts" / "evaluate-with-keychain.swift"
SOURCES = ROOT / "Tools" / "Corpus" / "sources.json"
AUTHORED = Path(__file__).with_name("authored.toml")
PROFILES = Path(__file__).with_name("profiles.json")
Z95 = 1.959963984540054

AGENCIES = (
    "brightwater-creative",
    "harbor-and-pine",
    "lumen-collective",
    "fieldnote-agency",
    "copperleaf-media",
    "tidewell-group",
    "oakridge-strategy",
    "meridian-loop",
    "sablestone-partners",
    "quillfeather-marketing",
    "northbay-brandworks",
    "juniper-signal",
)
PLACEHOLDER = re.compile(r"\[[^\]\n]*\]")
SIGN_OFF = re.compile(
    r"(?:best|warm|kind|warmest|many)?\s*(?:regards|best|thanks|thank you|sincerely|cheers"
    r"|all the best|warmly|best wishes|talk soon)[,.!]?",
    re.IGNORECASE,
)
SIGNATURE = re.compile(r"[A-Z][\w.'-]+(?: [A-Z][\w.'-]+){0,3}")
URL = re.compile(r"https?://[^\s<]+")
THEMES = (
    ("performance", ("performance", "review", "metric", "analys", "result", "roi")),
    ("partnership", ("partner", "collab", "synerg", "influencer")),
    ("event", ("webinar", "event", "festival", "conference", "summit")),
    ("proposal", ("idea", "thought", "explor", "opportunit", "propos", "rethink")),
)


def digest(data):
    """Return the lowercase SHA-256 of bytes, matching the evaluator's message hash."""
    return hashlib.sha256(data).hexdigest()


def write_json(path, value, exclusive=False):
    """Write readable UTF-8 JSON, refusing an existing file when `exclusive` is set."""
    with path.open("x" if exclusive else "w", encoding="utf-8") as stream:
        stream.write(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def read_json(path):
    """Read a UTF-8 JSON document."""
    return json.loads(path.read_text(encoding="utf-8"))


# Message set


def verified_source(downloads, source):
    """Return a pinned download's path after checking its recorded SHA-256."""
    path = downloads / source["filename"]
    if not path.is_file() or path.is_symlink():
        raise ValueError(f"source_file:{source['id']}")
    with path.open("rb") as stream:
        if hashlib.file_digest(stream, "sha256").hexdigest() != source["sha256"]:
            raise ValueError(f"source_hash:{source['id']}")
    return path


def ascii_slug(text, separator="."):
    """Fold a display name into a lowercase address-safe local part."""
    folded = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode()
    words = re.findall(r"[a-z0-9]+", folded.casefold())
    return separator.join(words)


def greeting_names(greeting):
    """Return the people a Marketeam greeting addresses, or an empty list for a team."""
    text = re.sub(r"^(hi|hello|dear)\s+", "", greeting.strip(), flags=re.IGNORECASE)
    text = text.rstrip(",:").strip()
    if not text or "team" in text.casefold():
        return []
    return [
        name.strip()
        for name in re.split(r",\s*(?:and\s+)?|\s+and\s+", text)
        if name.strip()
    ]


def marketeam_parts(text):
    """Split a Marketeam record into subject, greeting, body and signature name, or None."""
    lines = [line.strip() for line in text.strip().splitlines()]
    if not lines or not lines[0].startswith("Subject:"):
        return None
    subject = lines[0].removeprefix("Subject:").strip()
    body = "\n".join(lines[1:]).strip()
    greeting = next((line for line in lines[1:] if line), "")
    sign_offs = [index for index, line in enumerate(lines) if SIGN_OFF.fullmatch(line)]
    signature = (
        next((line for line in lines[sign_offs[-1] + 1 :] if line), "")
        if sign_offs
        else ""
    )
    if not subject or not SIGNATURE.fullmatch(signature):
        return None
    return subject, greeting, body, signature


def marketeam_stratum(subject, greeting):
    """Classify a record's content type by subject theme and audience, without labels."""
    lowered = subject.casefold()
    theme = next(
        (name for name, words in THEMES if any(w in lowered for w in words)), "other"
    )
    names = greeting_names(greeting)
    audience = (
        "team"
        if not names
        else "formal"
        if greeting.casefold().startswith("dear")
        else "group"
        if len(names) > 1
        else "individual"
    )
    return f"{theme}/{audience}"


def round_robin(groups, count, rnd):
    """Take `count` items spread evenly across shuffled strata."""
    queues = []
    for key in sorted(groups):
        items = list(groups[key])
        rnd.shuffle(items)
        queues.append(items)
    chosen = []
    while len(chosen) < count and any(queues):
        for queue in queues:
            if queue and len(chosen) < count:
                chosen.append(queue.pop())
    if len(chosen) < count:
        raise ValueError("marketeam_count")
    return chosen


def message_date(rnd):
    """Return a plausible delivery date in October 2026 with a North American offset."""
    zone = timezone(timedelta(hours=rnd.choice((-8, -7, -6, -5, -4))))
    start = datetime(2026, 10, 1, 8, tzinfo=zone)
    return format_datetime(
        start + timedelta(days=rnd.randrange(24), minutes=rnd.randrange(10 * 60))
    )


def message_id(rnd, domain):
    """Return a Message-ID that is unique within the set and stable for the seed."""
    return f"<{uuid.UUID(int=rnd.getrandbits(128)).hex}@{domain}>"


def html_version(subject, body):
    """Render plain paragraphs as a simple HTML alternative with linked URLs."""

    def paragraph(text):
        linked = URL.sub(
            lambda match: f'<a href="{match[0]}">{match[0]}</a>', html.escape(text)
        )
        return "<p>" + linked.replace("\n", "<br>\n") + "</p>"

    paragraphs = "\n".join(paragraph(text) for text in body.strip().split("\n\n"))
    return (
        '<!DOCTYPE html>\n<html><head><meta charset="utf-8">'
        f"<title>{html.escape(subject)}</title></head>\n"
        '<body style="font-family: Helvetica, Arial, sans-serif; max-width: 600px;">\n'
        f"{paragraphs}\n</body></html>\n"
    )


def email_bytes(headers, text, html_body=None, boundary=None):
    """Serialize an RFC 5322 message with CRLF line endings and a fixed MIME boundary."""
    message = EmailMessage(policy=policy.SMTP)
    for name, value in headers:
        message[name] = value
    message.set_content(text.strip() + "\n")
    if html_body:
        message.add_alternative(html_body, subtype="html")
        message.set_boundary(boundary)
    return message.as_bytes()


def marketeam_message(parts, rnd):
    """Wrap a Marketeam body as colleague mail from a fictional agency domain."""
    subject, greeting, body, signature = parts
    domain = f"{rnd.choice(AGENCIES)}.example"
    names = greeting_names(greeting)
    recipients = [f"{name} <{ascii_slug(name)}@{domain}>" for name in names] or [
        f"Marketing Team <marketing-team@{domain}>"
    ]
    headers = [
        ("From", f"{signature} <{ascii_slug(signature)}@{domain}>"),
        ("To", recipients[0]),
        *([("Cc", ", ".join(recipients[1:]))] if len(recipients) > 1 else []),
        ("Subject", subject),
        ("Date", message_date(rnd)),
        ("Message-ID", message_id(rnd, domain)),
    ]
    return email_bytes(headers, body)


def marketeam_messages(source, path, seed):
    """Sample Marketeam records reproducibly across subject themes and audiences."""
    groups = defaultdict(list)
    for position, raw in prepare.source_messages(source, path):
        text = raw.decode("utf-8")
        parts = marketeam_parts(text)
        if parts and not PLACEHOLDER.search(text) and 600 <= len(text) <= 3200:
            groups[marketeam_stratum(parts[0], parts[1])].append((position, parts))
    rnd = random.Random(f"{seed}:marketeam")
    chosen = round_robin(groups, MARKETEAM_COUNT, rnd)
    return [
        {
            "source": source["id"],
            "record": position,
            "synthetic": True,
            "raw": marketeam_message(parts, rnd),
        }
        for position, parts in sorted(chosen, key=lambda item: int(item[0]))
    ]


def authored_messages(seed):
    """Build every authored template as a synthetic message."""
    spec = tomllib.loads(AUTHORED.read_text(encoding="utf-8"))
    rnd = random.Random(f"{seed}:authored")
    entries = []
    for template in spec["message"]:
        sender = getaddresses([template["from"]])[0][1]
        domain = sender.rpartition("@")[2]
        headers = [
            ("From", template["from"]),
            ("To", spec["recipients"][template["language"]]),
            ("Subject", template["subject"]),
            ("Date", message_date(rnd)),
            ("Message-ID", message_id(rnd, domain)),
        ]
        if template["bulk"]:
            headers += [
                (
                    "List-Unsubscribe",
                    f"<https://{domain}/unsubscribe>, <mailto:unsubscribe@{domain}>",
                ),
                ("List-Unsubscribe-Post", "List-Unsubscribe=One-Click"),
            ]
        html_body = (
            html_version(template["subject"], template["body"])
            if template["bulk"]
            else None
        )
        entries.append(
            {
                "source": "authored",
                "record": template["key"],
                "synthetic": True,
                "raw": email_bytes(
                    headers,
                    template["body"],
                    html_body,
                    f"=_{rnd.getrandbits(64):016x}",
                ),
            }
        )
    return entries


def usable_threat(raw):
    """Whether a public spam or phishing sample parses with exactly one sender address."""
    if len(raw) > MAX_THREAT_BYTES:
        return False
    try:
        prepare.message_text(raw)
        message = BytesParser(policy=policy.default).parsebytes(raw)
        senders = getaddresses([str(message.get("From", ""))])
    except (ValueError, UnicodeError, LookupError, IndexError, RecursionError):
        return False
    return len(senders) == 1 and "@" in senders[0][1]


def threat_messages(source, path, count, seed):
    """Sample unmodified public spam or phishing controls reproducibly."""
    candidates = [
        (position, raw)
        for position, raw in prepare.source_messages(source, path)
        if usable_threat(raw)
    ]
    chosen = random.Random(f"{seed}:{source['id']}").sample(candidates, count)
    return [
        {"source": source["id"], "record": position, "synthetic": False, "raw": raw}
        for position, raw in sorted(chosen, key=lambda item: int(item[0]))
    ]


def assign_ids(entries, seed):
    """Shuffle every source together so message ids reveal nothing about origin."""
    entries = sorted(entries, key=lambda entry: (entry["source"], str(entry["record"])))
    random.Random(f"{seed}:ids").shuffle(entries)
    width = max(3, len(str(len(entries))))
    return {f"m{index:0{width}d}": entry for index, entry in enumerate(entries, 1)}


def build(downloads, output, seed, intent=None, private=None):
    """Write the blind message set and manifest; intended categories go only to `private`."""
    if output.exists() or output.is_symlink():
        raise ValueError("output_exists")
    if (intent is None) != (private is None):
        raise ValueError("intent_requires_private")
    sources = {source["id"]: source for source in read_json(SOURCES)}
    entries = authored_messages(seed)
    marketeam = sources[MARKETEAM]
    entries += marketeam_messages(
        marketeam, verified_source(downloads, marketeam), seed
    )
    for source_id, count in THREAT_COUNTS.items():
        source = sources[source_id]
        entries += threat_messages(
            source, verified_source(downloads, source), count, seed
        )
    hashes = Counter(digest(entry["raw"]) for entry in entries)
    if max(hashes.values()) > 1:
        raise ValueError("duplicate_message")
    messages = assign_ids(entries, seed)
    intents = authored_intents(intent, messages) if intent else None
    output.parent.mkdir(parents=True, exist_ok=True)
    output.mkdir(mode=0o700)
    for message, entry in messages.items():
        (output / f"{message}.eml").write_bytes(entry["raw"])
    used = [MARKETEAM, *THREAT_COUNTS]
    manifest = {
        "schema": MESSAGES_SCHEMA,
        "seed": seed,
        "sources": {
            source_id: {
                key: sources[source_id][key]
                for key in ("sha256", "url", "license", "attribution", "synthetic")
            }
            for source_id in used
        }
        | {
            "authored": {
                "file": str(AUTHORED.relative_to(ROOT)),
                "sha256": digest(AUTHORED.read_bytes()),
                "synthetic": True,
            }
        },
        "counts": dict(
            sorted(Counter(entry["source"] for entry in messages.values()).items())
        ),
        "messages": [
            {
                "id": message,
                "source": entry["source"],
                "record": entry["record"],
                "synthetic": entry["synthetic"],
                "sha256": digest(entry["raw"]),
            }
            for message, entry in messages.items()
        ],
    }
    write_json(output / "manifest.json", manifest, exclusive=True)
    if intents:
        private.mkdir(mode=0o700, parents=True, exist_ok=True)
        write_json(private / "authored-intent.json", intents, exclusive=True)
    return manifest


def authored_intents(path, messages):
    """Key the author's intended categories by message id; never shown to labelers."""
    intended = read_json(path)
    templates = {
        entry["record"]: message
        for message, entry in messages.items()
        if entry["source"] == "authored"
    }
    if set(intended) != set(templates) or not set(intended.values()) <= set(CATEGORIES):
        raise ValueError("authored_intents")
    return {
        "schema": "spamwise-adherence-authored-intent-v1",
        "note": "Author's intended categories for synthetic messages; not labels.",
        "intents": {
            templates[key]: {"template": key, "category": intended[key]}
            for key in sorted(templates, key=templates.get)
        },
    }


def load_manifest(directory):
    """Read a message manifest and verify every listed file's hash."""
    manifest = read_json(directory / "manifest.json")
    messages = {}
    for entry in manifest["messages"]:
        raw = (directory / f"{entry['id']}.eml").read_bytes()
        if digest(raw) != entry["sha256"]:
            raise ValueError(f"message_hash:{entry['id']}")
        messages[entry["id"]] = raw
    return manifest, messages


# Labels


def load_labeler(path, ids):
    """Read one labeler's file, rejecting unknown ids and categories."""
    document = read_json(path)
    labels = document.get("labels")
    if not isinstance(document.get("labeler"), str) or not isinstance(labels, dict):
        raise TypeError(f"labeler_format:{path.name}")
    if not set(labels) <= ids:
        raise ValueError(f"labeler_ids:{path.name}")
    if not set(labels.values()) <= set(CATEGORIES):
        raise ValueError(f"labeler_categories:{path.name}")
    return document


def agreement(pairs):
    """Raw agreement, chance agreement and Cohen's kappa for paired labels."""
    if not pairs:
        return {
            "jointly_labeled": 0,
            "agreed": 0,
            "raw": None,
            "chance": None,
            "kappa": None,
        }
    agreed = sum(first == second for first, second in pairs)
    observed = agreed / len(pairs)
    firsts, seconds = Counter(p[0] for p in pairs), Counter(p[1] for p in pairs)
    chance = sum(firsts[c] * seconds[c] for c in firsts) / len(pairs) ** 2
    return {
        "jointly_labeled": len(pairs),
        "agreed": agreed,
        "raw": observed,
        "chance": chance,
        "kappa": None if chance == 1 else (observed - chance) / (1 - chance),
    }


def stratified_split(labels, seed):
    """Split each category's ids in half by a seeded shuffle, alternating odd remainders."""
    splits = {"dev": [], "holdout": []}
    extra_to_dev = True
    for category in sorted(set(labels.values())):
        ids = sorted(message for message, label in labels.items() if label == category)
        random.Random(f"{seed}:split:{category}").shuffle(ids)
        half = len(ids) // 2
        if len(ids) % 2:
            half += extra_to_dev
            extra_to_dev = not extra_to_dev
        splits["dev"] += ids[:half]
        splits["holdout"] += ids[half:]
    return {name: sorted(ids) for name, ids in splits.items()}


def freeze(messages, label_paths, output, seed):
    """Keep only labels both labelers agree on and freeze a stratified dev/holdout split."""
    if output.exists() or output.is_symlink():
        raise FileExistsError(f"frozen_exists:{output}")
    manifest_path = messages / "manifest.json"
    ids = {entry["id"] for entry in read_json(manifest_path)["messages"]}
    first, second = (load_labeler(path, ids) for path in label_paths)
    if first["labeler"] == second["labeler"]:
        raise ValueError("labelers_not_distinct")
    joint = sorted(set(first["labels"]) & set(second["labels"]))
    pairs = [(first["labels"][i], second["labels"][i]) for i in joint]
    agreed = {
        i: first["labels"][i]
        for i in joint
        if first["labels"][i] == second["labels"][i]
    }
    excluded = [
        {
            "id": message,
            "reason": "disagreement" if message in joint else "missing",
            "labels": {
                document["labeler"]: document["labels"].get(message)
                for document in (first, second)
            },
        }
        for message in sorted(ids - set(agreed))
    ]
    splits = stratified_split(agreed, seed)
    split_of = {
        message: name for name, members in splits.items() for message in members
    }
    frozen = {
        "schema": LABELS_SCHEMA,
        "seed": seed,
        "manifest_sha256": digest(manifest_path.read_bytes()),
        "labelers": [
            {"labeler": document["labeler"], "sha256": digest(path.read_bytes())}
            for document, path in zip((first, second), label_paths, strict=True)
        ],
        "messages": len(ids),
        "agreement": agreement(pairs),
        "excluded": excluded,
        "labels": {
            message: {"category": agreed[message], "split": split_of[message]}
            for message in sorted(agreed)
        },
        "splits": splits,
        "category_counts": {
            category: {
                name: sum(agreed[message] == category for message in members)
                for name, members in splits.items()
            }
            for category in CATEGORIES
            if category in agreed.values()
        },
    }
    output.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    write_json(output, frozen, exclusive=True)
    return frozen


# Runs


def load_profiles():
    """Read the preference profiles, requiring a valid choice for every graymail category."""
    profiles = read_json(PROFILES)["profiles"]
    for name, choices in profiles.items():
        if set(choices) != set(GRAYMAIL) or not set(choices.values()) <= set(
            PREFERENCE_ACTIONS
        ):
            raise ValueError(f"profile:{name}")
    return profiles


def expected_action(preferences, category):
    """The action a profile calls for, or None for spam and scams, which are scored separately."""
    if category in THREATS:
        return None
    return (
        PREFERENCE_ACTIONS[preferences[category]] if category in GRAYMAIL else "inbox"
    )


def state_for(preferences):
    """An AppState with only this profile's preferences: no rules, Contacts, history or trust."""
    return {
        "revision": 0,
        "settings": {
            "strength": "balanced",
            "review": "orangeFlag",
            "dryRun": True,
            "paused": False,
            "categoryPreferences": preferences,
            "validatedAccounts": [],
        },
        "rules": [],
        "contentRules": [],
        "corrections": [],
        "records": [],
        "retries": [],
        "histories": {},
        "claimedActions": {},
        "ownAddresses": [],
    }


def mock_responses(messages):
    """Deterministic offline verdicts keyed by message hash; plumbing only, never labels."""
    responses = {}
    for raw in messages.values():
        sha = digest(raw)
        draw = hashlib.sha256(f"mock:{sha}".encode()).digest()
        category = CATEGORIES[draw[0] % len(CATEGORIES)]
        responses[sha] = {
            "label": "junk"
            if category in THREATS
            else ("inbox", "review", "junk")[draw[1] % 3],
            "category": category,
            "confidence": 50 + draw[2] % 51,
            "categoryConfidence": 50 + draw[3] % 51,
            "reason": "Offline mock: plumbing check, not a model result",
            "usage": {"input": 0, "output": 0, "cached": 0, "estimated": True},
        }
    return responses


@dataclass(frozen=True)
class RunConfig:
    """How each evaluator invocation runs: offline mock or live Claude through the launcher."""

    executable: Path
    live: bool = False
    budget_store: Path | None = None
    budget_limit: float | None = None
    reservation: float = RESERVATION_USD
    mock_responses: Path | None = None
    timeout: float = 3600


def pass_command(config, corpus, state, cache, report, replay_store):
    """One corpus invocation; a replay pass uses a zero-ceiling ledger so it cannot spend."""
    arguments = [
        "corpus",
        str(corpus),
        "--state",
        str(state),
        "--strength",
        "balanced",
        "--cache",
        str(cache),
        "--output",
        str(report),
    ]
    if not config.live:
        return [
            str(config.executable),
            *arguments,
            "--model",
            "mock",
            "--mock-responses",
            str(config.mock_responses),
        ]
    store, limit = (
        (replay_store, 0.0)
        if replay_store
        else (config.budget_store, config.budget_limit)
    )
    return [
        "swift",
        str(LAUNCHER),
        str(config.executable),
        "claude",
        "--live",
        *arguments,
        "--budget-store",
        str(store),
        "--budget-limit",
        str(limit),
        "--reservation",
        str(config.reservation),
    ]


def pass_problem(report, count, replay):
    """Why a pass cannot be used, or None: every message classified, a replay fully cached."""
    metrics = report["metrics"]
    if sum(sum(row.values()) for row in metrics["confusion"].values()) != count:
        return "incomplete_report"
    if metrics["unclassified"]:
        return "unclassified_messages"
    if report["failedProviderCalls"]:
        return "failed_provider_calls"
    if replay and (report["providerCalls"] or report["cacheHits"] != count):
        return "replay_not_cached"
    return None


OBSERVATION_FIELDS = (
    "label",
    "modelLabel",
    "confidence",
    "category",
    "categoryConfidence",
    "preference",
    "path",
    "concealsContent",
    "reason",
)


def merge_passes(inbox_report, junk_report, ids):
    """
    Recover every message's result from two passes over identical bytes.

    The evaluator lists only results that differ from the folder's expected label, so the pass
    with everything under good/ lists every non-Inbox result and the pass under junk/ every
    non-Junk result.
    """
    rows = {}
    for report in (inbox_report, junk_report):
        for row in report["metrics"]["misclassifications"]:
            message = Path(row["file"]).stem
            observation = {key: row[key] for key in OBSERVATION_FIELDS if key in row}
            if rows.setdefault(message, observation) != observation:
                raise ValueError(f"inconsistent_passes:{message}")
    if set(rows) != set(ids):
        raise ValueError("missing_observations")
    return dict(sorted(rows.items()))


def invoke(command, timeout, stderr_path):
    """
    Run one evaluator command in its own process group and return its exit status.

    On timeout the whole group is killed, so the evaluator the Keychain launcher started cannot
    outlive it.
    """
    with stderr_path.open("wb") as stderr:
        process = subprocess.Popen(
            command, stdout=subprocess.DEVNULL, stderr=stderr, start_new_session=True
        )
        try:
            return process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
            raise


def run_profile(config, directory, name, preferences, messages):
    """Evaluate one profile in an isolated directory, stopping at the first unusable pass."""
    directory.mkdir(mode=0o700)
    state = directory / "state.json"
    write_json(state, state_for(preferences), exclusive=True)
    result = {"profile": name, "state_sha256": digest(state.read_bytes())}
    reports = {}
    for pass_name, folder in (("inbox", "good"), ("junk", "junk")):
        corpus = directory / f"corpus-{pass_name}"
        (corpus / folder).mkdir(parents=True)
        for message, raw in messages.items():
            (corpus / folder / f"{message}.eml").write_bytes(raw)
        replay = pass_name == "junk"
        report_path = directory / f"report-{pass_name}.json"
        command = pass_command(
            config,
            corpus,
            state,
            directory / "cache",
            report_path,
            directory / "replay-budget.store" if replay else None,
        )
        status = invoke(command, config.timeout, directory / f"{pass_name}.stderr.txt")
        if status != 0:
            return {**result, "status": f"{pass_name}_pass_exit_{status}"}
        report = read_json(report_path)
        if problem := pass_problem(report, len(messages), replay):
            return {**result, "status": f"{pass_name}_pass_{problem}"}
        reports[pass_name] = report
    observations = merge_passes(reports["inbox"], reports["junk"], messages)
    first = reports["inbox"]
    write_json(
        directory / "observations.json",
        {
            "profile": name,
            "preferences": preferences,
            "model": first["model"],
            "strength": first["strength"],
            "observations": observations,
        },
        exclusive=True,
    )
    return {
        **result,
        "status": "completed",
        "model": first["model"],
        "provider_calls": first["providerCalls"],
        "cache_hits": first["cacheHits"],
        "new_usage": first["newUsage"],
        "estimated_cost_usd": first.get("newEstimatedCostUSD"),
        "category_confidence": any(
            "categoryConfidence" in row for row in observations.values()
        ),
    }


def execute(config, tag_directory, profiles, messages, metadata):
    """Run profiles sequentially without retry or fallback, stopping after the first failure."""
    results = []
    for name, preferences in profiles.items():
        try:
            result = run_profile(
                config, tag_directory / name, name, preferences, messages
            )
        except (OSError, ValueError, KeyError, subprocess.TimeoutExpired) as error:
            result = {"profile": name, "status": f"interrupted:{type(error).__name__}"}
        results.append(result)
        write_json(
            tag_directory / "run.json",
            {
                **metadata,
                "maximum_reservation_usd": round(
                    len(results) * len(messages) * config.reservation, 4
                )
                if config.live
                else 0,
                "completed": len(results) == len(profiles)
                and result["status"] == "completed",
                "profiles": results,
            },
        )
        if result["status"] != "completed":
            break
    return results


def run(config, messages_directory, output, tag, commit=None, selected=None):
    """Prepare one tag's isolated per-profile runs over the frozen message bytes."""
    if not re.fullmatch(r"[A-Za-z0-9._-]+", tag):
        raise ValueError("tag")
    profiles = load_profiles()
    if selected:
        if not set(selected) <= set(profiles):
            raise ValueError("unknown_profile")
        profiles = {name: profiles[name] for name in profiles if name in selected}
    manifest_path = messages_directory / "manifest.json"
    _, messages = load_manifest(messages_directory)
    metadata = {
        "tag": tag,
        "mode": "live" if config.live else "offline_mock",
        "model": LIVE_MODEL if config.live else "mock",
        "executable": str(config.executable),
        "executable_sha256": digest(config.executable.read_bytes()),
        "commit": commit,
        "messages_manifest_sha256": digest(manifest_path.read_bytes()),
        "messages": len(messages),
        "reservation_usd": config.reservation if config.live else None,
    }
    tag_directory = output / tag
    output.mkdir(mode=0o700, parents=True, exist_ok=True)
    tag_directory.mkdir(mode=0o700)
    if not config.live:
        mock_path = tag_directory / "mock-responses.json"
        write_json(mock_path, mock_responses(messages), exclusive=True)
        config = RunConfig(
            executable=config.executable,
            mock_responses=mock_path,
            timeout=config.timeout,
        )
    return execute(config, tag_directory, profiles, messages, metadata)


# Scores


def wilson(successes, total):
    """Wilson score 95% interval, or None without observations."""
    if not total:
        return None
    p = successes / total
    denominator = 1 + Z95**2 / total
    center = (p + Z95**2 / (2 * total)) / denominator
    half = Z95 * math.sqrt(p * (1 - p) / total + Z95**2 / (4 * total**2)) / denominator
    return [max(0.0, center - half), min(1.0, center + half)]


def rate(count, total):
    """A count with its denominator, rate and Wilson interval."""
    return {
        "count": count,
        "total": total,
        "rate": count / total if total else None,
        "wilson95": wilson(count, total),
    }


def effective(row):
    """The evaluator's effective label, naming a missing one."""
    return row.get("label") or "unclassified"


def swept_action(row, preferences, threshold):
    """Junk at or above `threshold` category confidence for a Junk-preferred category, else Review."""
    category = row.get("category")
    if (
        threshold is not None
        and row.get("path") == "model"
        and category in GRAYMAIL
        and preferences[category] == "junk"
        and row.get("categoryConfidence") is not None
    ):
        return "junk" if row["categoryConfidence"] >= threshold else "review"
    return effective(row)


def items_for(observations, preferences, labels, split, threshold=None):
    """Pair each frozen message in `split` with its expected and effective actions."""
    return [
        {
            "id": message,
            "truth": label["category"],
            "expected": expected_action(preferences, label["category"]),
            "effective": swept_action(observations[message], preferences, threshold),
            "model_category": observations[message].get("category"),
        }
        for message, label in labels.items()
        if label["split"] == split
    ]


def summarize(items):
    """Adherence, action confusion, Junk errors, Review burden, category accuracy and spam path."""
    scored = [item for item in items if item["expected"]]
    threats = [item for item in items if not item["expected"]]
    keep = [item for item in scored if item["expected"] != "junk"]
    junk = [item for item in scored if item["expected"] == "junk"]
    wrong = sorted(item["id"] for item in keep if item["effective"] == "junk")
    missed = sorted(item["id"] for item in junk if item["effective"] != "junk")
    confusion = defaultdict(Counter)
    for item in scored:
        confusion[item["expected"]][item["effective"]] += 1
    categories = defaultdict(Counter)
    for item in items:
        categories[item["truth"]][item["model_category"] or "none"] += 1
    outcomes = Counter(item["effective"] for item in threats)
    return {
        "messages": len(items),
        "adherence": rate(
            sum(i["expected"] == i["effective"] for i in scored), len(scored)
        ),
        "confusion": {
            expected: {action: confusion[expected][action] for action in ACTIONS}
            for expected in ("inbox", "review", "junk")
            if confusion[expected]
        },
        "wrong_junk": {**rate(len(wrong), len(keep)), "ids": wrong},
        "missed_junk": {**rate(len(missed), len(junk)), "ids": missed},
        "review_burden": rate(
            sum(i["effective"] == "review" for i in scored), len(scored)
        ),
        "category_accuracy": rate(
            sum(i["truth"] == i["model_category"] for i in items), len(items)
        ),
        "category_confusion": {
            truth: dict(row) for truth, row in sorted(categories.items())
        },
        "spam_path": {
            "outcomes": {action: outcomes[action] for action in ACTIONS},
            "caught": rate(outcomes["junk"] + outcomes["review"], len(threats)),
            "inbox_ids": sorted(
                item["id"] for item in threats if item["effective"] == "inbox"
            ),
        },
    }


def sweep_summary(items):
    """The headline measures for one threshold."""
    summary = summarize(items)
    return {
        key: summary[key]
        for key in ("adherence", "wrong_junk", "missed_junk", "review_burden")
    }


def check_preferences(tag, name, observations, preferences):
    """Refuse results whose recorded preference differs from the profile's state."""
    for message, row in observations.items():
        category = row.get("category")
        if (
            row.get("path") == "model"
            and category in GRAYMAIL
            and row.get("preference") != preferences[category]
        ):
            raise ValueError(f"preference_mismatch:{tag}/{name}/{message}")


def score_tag(runs, tag, frozen):
    """Score one tag's completed profiles on dev and holdout, with a sweep when available."""
    run_report = read_json(runs / tag / "run.json")
    if run_report["messages_manifest_sha256"] != frozen["manifest_sha256"]:
        raise ValueError(f"manifest_mismatch:{tag}")
    labels = frozen["labels"]
    profiles = {}
    for result in run_report["profiles"]:
        if result["status"] != "completed":
            continue
        document = read_json(runs / tag / result["profile"] / "observations.json")
        check_preferences(
            tag, result["profile"], document["observations"], document["preferences"]
        )
        profiles[result["profile"]] = document
    model_rows = [
        row
        for document in profiles.values()
        for row in document["observations"].values()
        if row.get("path") == "model"
    ]
    has_confidence = bool(model_rows) and all(
        "categoryConfidence" in row for row in model_rows
    )

    def measured(split, threshold, measure):
        per_profile = {
            name: items_for(
                document["observations"],
                document["preferences"],
                labels,
                split,
                threshold,
            )
            for name, document in profiles.items()
        }
        return {
            "overall": measure(
                [item for items in per_profile.values() for item in items]
            ),
            "profiles": {name: measure(items) for name, items in per_profile.items()},
        }

    return {
        "run": {
            key: run_report.get(key)
            for key in ("mode", "model", "commit", "executable_sha256", "completed")
        },
        "profiles_scored": list(profiles),
        "profiles_incomplete": [
            result["profile"]
            for result in run_report["profiles"]
            if result["status"] != "completed"
        ],
        "category_confidence": has_confidence,
        "splits": {split: measured(split, None, summarize) for split in SPLITS},
        "sweep": {
            split: [
                {"threshold": threshold, **measured(split, threshold, sweep_summary)}
                for threshold in SWEEP_THRESHOLDS
            ]
            for split in SPLITS
        }
        if has_confidence
        else None,
    }


def intent_check(intent_path, frozen):
    """Compare authored intent with frozen labels; disagreement flags a template, not a labeler."""
    intents = read_json(intent_path)["intents"]
    frozen_ids = [message for message in intents if message in frozen["labels"]]
    mismatches = {
        message: {
            "template": intents[message]["template"],
            "intent": intents[message]["category"],
            "frozen": frozen["labels"][message]["category"],
        }
        for message in frozen_ids
        if intents[message]["category"] != frozen["labels"][message]["category"]
    }
    return {
        "authored": len(intents),
        "frozen": len(frozen_ids),
        "matching": rate(len(frozen_ids) - len(mismatches), len(frozen_ids)),
        "mismatches": mismatches,
    }


def score(frozen_path, runs, tags, output, intent=None):
    """Write JSON and Markdown adherence summaries for one or more binary tags."""
    if output.exists() or output.is_symlink():
        raise ValueError("output_exists")
    frozen = read_json(frozen_path)
    report = {
        "schema": SCORE_SCHEMA,
        "frozen_sha256": digest(frozen_path.read_bytes()),
        "agreement": frozen["agreement"],
        "split_sizes": {split: len(frozen["splits"][split]) for split in SPLITS},
        "tags": {tag: score_tag(runs, tag, frozen) for tag in tags},
    }
    if intent:
        report["intent_check"] = intent_check(intent, frozen)
    output.mkdir(mode=0o700, parents=True)
    write_json(output / "score.json", report, exclusive=True)
    with (output / "score.md").open("x", encoding="utf-8") as stream:
        stream.write(markdown(report))
    return report


def percent(value):
    """Format a rate as a percentage, or a dash without one."""
    return "–" if value is None else f"{value * 100:.1f}%"


def with_interval(measure):
    """Format a rate with its count and Wilson interval."""
    interval = measure["wilson95"]
    bounds = f" ({percent(interval[0])}–{percent(interval[1])})" if interval else ""
    return f"{measure['count']}/{measure['total']} {percent(measure['rate'])}{bounds}"


def markdown(report):
    """Render the headline measures as Markdown tables."""
    agreement_stats = report["agreement"]
    kappa = agreement_stats["kappa"]
    lines = [
        "# Preference adherence",
        "",
        (
            f"Frozen labels: dev {report['split_sizes']['dev']}, holdout "
            f"{report['split_sizes']['holdout']}; raw agreement {percent(agreement_stats['raw'])}, "
            f"Cohen's kappa {'–' if kappa is None else f'{kappa:.3f}'}."
        ),
        "",
        (
            "Adherence: effective action equals the profile's expected action (spam and scams "
            "excluded). Wrong Junk: expected Inbox or Review but Junk. Missed Junk: expected Junk "
            "but not Junk. Review burden: share of adherence-scored messages flagged for Review. "
            "Intervals are Wilson 95%."
        ),
    ]
    for tag, scored in report["tags"].items():
        run_info = scored["run"]
        lines += [
            "",
            f"## {tag}",
            "",
            (
                f"Mode {run_info['mode']}, model {run_info['model']}, commit "
                f"{run_info['commit'] or 'unrecorded'}. Incomplete profiles: "
                f"{', '.join(scored['profiles_incomplete']) or 'none'}."
            ),
        ]
        for split in SPLITS:
            measures = scored["splits"][split]
            lines += [
                "",
                f"### {split}",
                "",
                (
                    "| Profile | Adherence | Wrong Junk | Missed Junk | Review burden "
                    "| Category accuracy | Spam path caught |"
                ),
                "| --- | --- | --- | --- | --- | --- | --- |",
            ]
            rows = [*measures["profiles"].items(), ("overall", measures["overall"])]
            for name, summary in rows:
                lines.append(
                    f"| {name} | {with_interval(summary['adherence'])} "
                    f"| {with_interval(summary['wrong_junk'])} "
                    f"| {summary['missed_junk']['count']}/{summary['missed_junk']['total']} "
                    f"| {percent(summary['review_burden']['rate'])} "
                    f"| {percent(summary['category_accuracy']['rate'])} "
                    f"| {summary['spam_path']['caught']['count']}/"
                    f"{summary['spam_path']['caught']['total']} |"
                )
            wrong = [
                f"{name}: {', '.join(summary['wrong_junk']['ids'])}"
                for name, summary in measures["profiles"].items()
                if summary["wrong_junk"]["ids"]
            ]
            if wrong:
                lines += ["", "Wrong-Junk ids — " + "; ".join(wrong) + "."]
        if scored["sweep"]:
            for split in SPLITS:
                lines += [
                    "",
                    f"### Category-confidence sweep, {split} (all profiles)",
                    "",
                    "| Threshold | Adherence | Wrong Junk | Missed Junk | Review burden |",
                    "| --- | --- | --- | --- | --- |",
                ]
                for point in scored["sweep"][split]:
                    overall = point["overall"]
                    lines.append(
                        f"| {point['threshold']} | {with_interval(overall['adherence'])} "
                        f"| {with_interval(overall['wrong_junk'])} "
                        f"| {overall['missed_junk']['count']}/{overall['missed_junk']['total']} "
                        f"| {percent(overall['review_burden']['rate'])} |"
                    )
        else:
            lines += [
                "",
                "No category confidence in these reports; no threshold sweep.",
            ]
    if check := report.get("intent_check"):
        lines += [
            "",
            "## Authored intent check",
            "",
            (
                f"Frozen labels match the author's intent for {with_interval(check['matching'])} "
                "of frozen authored messages."
            ),
        ]
    return "\n".join(lines) + "\n"


# Command line


def main():
    """Build the message set, freeze labels, run profiles or score reports."""
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    build_parser = commands.add_parser("build", help="Write the blind message set.")
    build_parser.add_argument("--downloads", type=Path, required=True)
    build_parser.add_argument("--output", type=Path, required=True)
    build_parser.add_argument("--intent", type=Path)
    build_parser.add_argument("--private", type=Path)
    build_parser.add_argument("--seed", default=SEED)
    freeze_parser = commands.add_parser(
        "freeze", help="Freeze agreed labels and splits."
    )
    freeze_parser.add_argument("--messages", type=Path, required=True)
    freeze_parser.add_argument("--labels", type=Path, nargs=2, required=True)
    freeze_parser.add_argument("--output", type=Path, required=True)
    freeze_parser.add_argument("--seed", default=SEED)
    run_parser = commands.add_parser(
        "run", help="Evaluate every profile for one binary."
    )
    run_parser.add_argument("--executable", type=Path, required=True)
    run_parser.add_argument("--tag", required=True)
    run_parser.add_argument("--messages", type=Path, required=True)
    run_parser.add_argument("--output", type=Path, required=True)
    run_parser.add_argument("--commit")
    run_parser.add_argument("--profile", action="append")
    run_parser.add_argument("--live", action="store_true")
    run_parser.add_argument("--budget-store", type=Path)
    run_parser.add_argument("--budget-limit", type=float)
    run_parser.add_argument("--reservation", type=float, default=RESERVATION_USD)
    run_parser.add_argument("--timeout", type=float, default=3600)
    score_parser = commands.add_parser(
        "score", help="Summarize adherence for binary tags."
    )
    score_parser.add_argument("--frozen", type=Path, required=True)
    score_parser.add_argument("--runs", type=Path, required=True)
    score_parser.add_argument("--tag", action="append", required=True)
    score_parser.add_argument("--output", type=Path, required=True)
    score_parser.add_argument("--intent", type=Path)
    args = parser.parse_args()
    previous_umask = os.umask(0o077)
    try:
        match args.command:
            case "build":
                manifest = build(
                    args.downloads.resolve(),
                    args.output.absolute(),
                    args.seed,
                    args.intent,
                    args.private and args.private.absolute(),
                )
                summary = {
                    "messages": len(manifest["messages"]),
                    "counts": manifest["counts"],
                }
            case "freeze":
                frozen = freeze(args.messages, args.labels, args.output, args.seed)
                summary = {
                    "agreement": frozen["agreement"],
                    "excluded": len(frozen["excluded"]),
                    "splits": {
                        name: len(ids) for name, ids in frozen["splits"].items()
                    },
                }
            case "run":
                if args.live != (
                    args.budget_store is not None and args.budget_limit is not None
                ):
                    parser.error(
                        "--live requires --budget-store and --budget-limit, and only it does"
                    )
                results = run(
                    RunConfig(
                        executable=args.executable.resolve(),
                        live=args.live,
                        budget_store=args.budget_store and args.budget_store.resolve(),
                        budget_limit=args.budget_limit,
                        reservation=args.reservation,
                        timeout=args.timeout,
                    ),
                    args.messages.resolve(),
                    args.output.absolute(),
                    args.tag,
                    args.commit,
                    args.profile,
                )
                summary = {result["profile"]: result["status"] for result in results}
            case "score":
                report = score(
                    args.frozen, args.runs, args.tag, args.output, args.intent
                )
                summary = {
                    tag: {
                        split: scored["splits"][split]["overall"]["adherence"]["rate"]
                        for split in SPLITS
                    }
                    for tag, scored in report["tags"].items()
                }
    except (ValueError, TypeError, OSError, KeyError) as error:
        parser.exit(1, f"{args.command} failed: {error}\n")
    finally:
        os.umask(previous_umask)
    print(json.dumps(summary, ensure_ascii=False))
    if args.command == "run" and any(
        status != "completed" for status in summary.values()
    ):
        sys.exit(1)


if __name__ == "__main__":
    main()
