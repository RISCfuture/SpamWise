#!/usr/bin/env python3
"""Validate or notarize a build using the existing encrypted Match API key."""

import argparse
import json
import os
import shlex
import subprocess
import tempfile
from pathlib import Path


def match_password(env_file):
    """Read only MATCH_PASSWORD from an existing project environment file."""
    for line in env_file.read_text().splitlines():
        key, separator, value = line.removeprefix("export ").partition("=")
        if separator and key.strip() == "MATCH_PASSWORD":
            parts = shlex.split(value, comments=True)
            if len(parts) == 1 and parts[0]:
                return parts[0]
    raise ValueError("MATCH_PASSWORD is absent or not a literal assignment")


def run(arguments):
    """Capture credential-consuming output and surface only sanitized failures."""
    result = subprocess.run(arguments, capture_output=True, check=False)
    if result.returncode:
        raise RuntimeError(
            f"{Path(arguments[0]).name} failed (exit {result.returncode})"
        )
    return result.stdout


def main():
    """Use a private temporary key file for one validation or notarization command."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--certificates", type=Path, required=True)
    parser.add_argument("--env-file", type=Path, required=True)
    action = parser.add_mutually_exclusive_group()
    action.add_argument("--archive", type=Path)
    action.add_argument("--validate-app", type=Path)
    parser.add_argument("--output", type=Path)
    options = parser.parse_args()
    environment = os.environ.copy()
    environment["MATCH_PASSWORD"] = match_password(options.env_file)
    helper = options.certificates.resolve() / "bin/api-key"
    decrypted = subprocess.run(
        [str(helper), "--stdout"], env=environment, capture_output=True, check=False
    )
    if decrypted.returncode:
        raise RuntimeError(
            "Match key decryption failed; check Ruby/fastlane and MATCH_PASSWORD"
        )
    key = json.loads(decrypted.stdout)
    with tempfile.TemporaryDirectory(prefix="SpamWise-notary-") as directory:
        key_path = Path(directory) / "AuthKey.p8"
        descriptor = os.open(key_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "w") as stream:
            stream.write(key["key"])
        if options.validate_app:
            command = [
                "xcrun",
                "altool",
                "--validate-app",
                str(options.validate_app.resolve()),
                "--api-key",
                key["key_id"],
                "--api-issuer",
                key["issuer_id"],
                "--p8-file-path",
                str(key_path),
                "--output-format",
                "json",
            ]
            completed = subprocess.run(command, capture_output=True, check=False)
            diagnostics = (completed.stdout + completed.stderr).decode(errors="replace")
            diagnostics = diagnostics.replace(
                key["key"].strip(), "[redacted private key]"
            )
            try:
                result = json.loads(diagnostics)
            except ValueError:
                result = {"exitCode": completed.returncode, "diagnostics": diagnostics}
            if options.output:
                options.output.write_text(json.dumps(result, indent=2) + "\n")
                options.output.chmod(0o600)
            if completed.returncode:
                raise RuntimeError(
                    "Store validation failed; inspect the saved JSON report"
                )
            print("Store validation passed. No app was uploaded or published.")
            return
        command = ["xcrun", "notarytool"]
        if options.archive:
            command += ["submit", str(options.archive.resolve()), "--wait"]
        else:
            command += ["history"]
        command += [
            "--key",
            str(key_path),
            "--key-id",
            key["key_id"],
            "--issuer",
            key["issuer_id"],
            "--output-format",
            "json",
        ]
        result = json.loads(run(command))
        if options.output:
            options.output.write_text(json.dumps(result, indent=2) + "\n")
        if options.archive:
            status = result.get("status", "Unknown")
            print(
                f"Notarization status: {status}; submission: {result.get('id', 'unknown')}"
            )
            if status != "Accepted":
                raise RuntimeError(
                    "Notarization did not succeed; inspect Apple's submission log"
                )
        else:
            print("Match API key authenticated with Apple's notarization service.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, RuntimeError) as error:
        raise SystemExit(str(error)) from None
