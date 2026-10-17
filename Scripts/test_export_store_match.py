"""Behavior checks for store signing's identity and keychain isolation boundaries."""

import hashlib
import runpy
import subprocess
import sys
import time
import unittest
from copy import deepcopy
from datetime import UTC, datetime, timedelta
from pathlib import Path
from unittest.mock import patch

HELPERS = runpy.run_path(str(Path(__file__).with_name("export-store-match.py")))
VALIDATE = HELPERS["validate_profile"]
KEYCHAIN = HELPERS["temporary_keychain"]


class StorePackagingTests(unittest.TestCase):
    def test_timeout_terminates_descendants_holding_output_open(self):
        """Credential cleanup returns even when a child ignores graceful termination."""
        child = "import signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); print('ready',flush=True); time.sleep(60)"
        parent = (
            "import subprocess,sys,time; "
            f"p=subprocess.Popen([sys.executable,'-c',{child!r}],stdout=subprocess.PIPE); "
            "p.stdout.readline(); print('ready',flush=True); time.sleep(60)"
        )
        started = time.monotonic()
        with self.assertRaises(subprocess.TimeoutExpired):
            HELPERS["run"]([sys.executable, "-c", parent], timeout=1)
        self.assertLess(time.monotonic() - started, 15)

    def test_rejects_incompatible_distribution_profiles(self):
        """Only the expected certificate, team and granted shared capabilities can sign."""
        certificate = b"synthetic certificate"
        fingerprint = hashlib.sha1(certificate).hexdigest().upper()
        entitlements = {
            "com.apple.application-identifier": "2NFSK2WB24.codes.tim.SpamWise",
            "com.apple.developer.team-identifier": "2NFSK2WB24",
            "com.apple.security.app-sandbox": True,
            "com.apple.security.application-groups": ["group.codes.tim.SpamWise"],
            "keychain-access-groups": ["2NFSK2WB24.codes.tim.SpamWise.shared"],
        }
        profile = {
            "Platform": ["OSX"],
            "TeamIdentifier": ["2NFSK2WB24"],
            "ExpirationDate": datetime.now(UTC) + timedelta(days=1),
            "DeveloperCertificates": [certificate],
            "Entitlements": {
                **entitlements,
                "keychain-access-groups": ["2NFSK2WB24.*"],
            },
        }
        VALIDATE(profile, "codes.tim.SpamWise", fingerprint, entitlements)
        for change in (
            {"Platform": ["iOS"]},
            {"ProvisionedDevices": []},
            {"ProvisionsAllDevices": True},
            {"TeamIdentifier": ["different-team"]},
            {"ExpirationDate": datetime.now(UTC) - timedelta(days=1)},
            {"DeveloperCertificates": [b"different certificate"]},
        ):
            with self.subTest(change=list(change)), self.assertRaises(ValueError):
                VALIDATE(
                    {**profile, **change},
                    "codes.tim.SpamWise",
                    fingerprint,
                    entitlements,
                )
        for key, value in (
            ("com.apple.application-identifier", "2NFSK2WB24.some.other.app"),
            ("com.apple.security.application-groups", []),
            ("keychain-access-groups", ["different-team.*"]),
            ("com.apple.security.get-task-allow", True),
        ):
            incompatible = deepcopy(profile)
            incompatible["Entitlements"][key] = value
            with self.subTest(capability=key), self.assertRaises(ValueError):
                VALIDATE(incompatible, "codes.tim.SpamWise", fingerprint, entitlements)

    def test_removes_only_owned_keychain_after_signing_failure(self):
        """Cleanup preserves unrelated entries added while the signing operation was running."""
        existing = ["/login.keychain-db"]
        deleted = []
        owned = "/private/example/signing.keychain-db"

        def run(arguments):
            command = arguments[1]
            if command == "create-keychain":
                existing.append(arguments[-1])
            elif command == "list-keychains":
                if "-s" in arguments:
                    existing[:] = arguments[arguments.index("-s") + 1 :]
                else:
                    return "\n".join(f'"{entry}"' for entry in existing).encode()
            elif command == "delete-keychain":
                deleted.append(arguments[-1])
            return b""

        with (
            patch.dict(HELPERS["search_list"].__globals__, run=run),
            self.assertRaisesRegex(RuntimeError, "signing failed"),
            KEYCHAIN(Path("/private/example")),
        ):
            existing.append("/another-session.keychain-db")
            raise RuntimeError("signing failed")
        self.assertEqual(
            existing, ["/login.keychain-db", "/another-session.keychain-db"]
        )
        self.assertEqual(deleted, [owned])


if __name__ == "__main__":
    unittest.main()
