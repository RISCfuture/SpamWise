#!/usr/bin/env python3
"""Export a local store package using an ephemeral keychain and existing Match keys."""

import argparse
import hashlib
import os
import plistlib
import runpy
import secrets
import shlex
import shutil
import signal
import subprocess
import tempfile
from contextlib import contextmanager
from datetime import UTC, datetime
from fnmatch import fnmatchcase
from pathlib import Path

DECRYPT = """\
# frozen_string_literal: true

$LOAD_PATH.unshift(File.join(Gem::Specification.find_by_name("fastlane").gem_dir, "match", "lib"))
require "match/encryption/encryption"
cipher = Match::Encryption::MatchDataEncryption.new
$stdout.binmode
$stdout.write(cipher.decrypt(base64encoded_encrypted: File.read(ARGV.fetch(0)),
                             password:                ENV.fetch("MATCH_PASSWORD")))
"""


def stop_process_tree(process):
    """Terminate the command and descendants captured before its parent exits."""
    listing = subprocess.run(
        ["ps", "-axo", "pid=,ppid="], capture_output=True, check=True, text=True
    ).stdout
    parents = {
        int(pid): int(parent) for pid, parent in map(str.split, listing.splitlines())
    }
    owned = {process.pid}
    while (
        descendants := {pid for pid, parent in parents.items() if parent in owned}
        - owned
    ):
        owned.update(descendants)
    signal_processes(process.pid, owned, signal.SIGTERM)
    try:
        process.communicate(timeout=5)
    except subprocess.TimeoutExpired:
        signal_processes(process.pid, owned, signal.SIGKILL)
        try:
            process.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            process.stdout.close()
            process.stderr.close()
            process.wait(timeout=5)


def signal_processes(group, owned, termination):
    """Signal the isolated command group and captured descendants that changed groups."""
    try:
        os.killpg(group, termination)
    except ProcessLookupError:
        pass
    for pid in sorted(owned, reverse=True):
        try:
            os.kill(pid, termination)
        except ProcessLookupError:
            pass


def run(arguments, timeout=30, **options):
    """Capture credential-consuming output without exposing arguments or raw failures."""
    process = subprocess.Popen(
        arguments,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        start_new_session=True,
        **options,
    )
    try:
        output, _ = process.communicate(timeout=timeout)
    except (subprocess.TimeoutExpired, KeyboardInterrupt):
        stop_process_tree(process)
        raise
    if process.returncode:
        raise RuntimeError(
            f"{Path(arguments[0]).name} failed (exit {process.returncode})"
        )
    return output


def search_list():
    """Read the user's current keychain search paths without credential values."""
    return shlex.split(run(["security", "list-keychains", "-d", "user"]).decode())


@contextmanager
def temporary_keychain(directory):
    """Create an explicitly addressed signing keychain without changing login-key permissions."""
    keychain = str(directory / "signing.keychain-db")
    password = secrets.token_urlsafe(32)
    run(["security", "create-keychain", "-p", password, keychain])
    try:
        run(["security", "unlock-keychain", "-p", password, keychain])
        run(["security", "set-keychain-settings", "-lut", "600", keychain])
        yield keychain, password
    finally:
        try:
            current = [entry for entry in search_list() if entry != keychain]
            run(["security", "list-keychains", "-d", "user", "-s", *current])
        finally:
            run(["security", "delete-keychain", keychain])


def import_identity(repository, kind, directory, keychain, environment):
    """Decrypt one existing Match identity into private temporary files and import it."""
    certificates = sorted((repository / "certs" / kind).glob("*.cer"))
    if len(certificates) != 1:
        raise ValueError(f"Expected exactly one reviewed {kind} certificate")
    certificate = certificates[0]
    certificate_bytes = run(["ruby", "-e", DECRYPT, str(certificate)], env=environment)
    private_bytes = run(
        ["ruby", "-e", DECRYPT, str(certificate.with_suffix(".p12"))], env=environment
    )
    for suffix, content in (("cer", certificate_bytes), ("p12", private_bytes)):
        path = directory / f"{kind}.{suffix}"
        with path.open("xb") as stream:
            stream.write(content)
        path.chmod(0o600)
        run(
            [
                "security",
                "import",
                str(path),
                "-k",
                keychain,
                "-P",
                "",
                "-T",
                "/usr/bin/codesign",
                "-T",
                "/usr/bin/productbuild",
                "-T",
                "/usr/bin/productsign",
            ]
        )
    return hashlib.sha1(certificate_bytes).hexdigest().upper()


def validate_profile(profile, identifier, certificate, entitlements):
    """Reject device, expired, wrong-team or capability-incompatible profiles."""
    allowed = profile.get("Entitlements", {})
    if (
        profile.get("TeamIdentifier") != ["2NFSK2WB24"]
        or profile.get("Platform") != ["OSX"]
        or "ProvisionedDevices" in profile
        or profile.get("ProvisionsAllDevices")
        or profile["ExpirationDate"].replace(tzinfo=UTC) <= datetime.now(UTC)
        or allowed.get("com.apple.application-identifier") != "2NFSK2WB24." + identifier
        or allowed.get("com.apple.security.get-task-allow", False)
        or certificate
        not in {
            hashlib.sha1(item).hexdigest().upper()
            for item in profile["DeveloperCertificates"]
        }
    ):
        raise ValueError(
            "Store profile identity, expiry or signing certificate mismatch"
        )
    for key in (
        "com.apple.application-identifier",
        "com.apple.developer.team-identifier",
    ):
        if entitlements.get(key) != allowed.get(key):
            raise ValueError("Archive identity does not match the profile")
    for key in ("keychain-access-groups", "com.apple.security.application-groups"):
        if any(
            not any(fnmatchcase(value, pattern) for pattern in allowed.get(key, []))
            for value in entitlements.get(key, [])
        ):
            raise ValueError("Archive capabilities do not match the profile")
    if entitlements.get("com.apple.security.app-sandbox") is not True:
        raise ValueError("App Sandbox must remain enabled")


def sign_bundle(bundle, profile_path, identifier, certificate, keychain, directory):
    """Preserve archived entitlements while embedding a compatible distribution profile."""
    info = plistlib.loads((bundle / "Contents/Info.plist").read_bytes())
    if info["CFBundleIdentifier"] != identifier:
        raise ValueError("Unexpected archive bundle identity")
    entitlements = plistlib.loads(
        run(["codesign", "-d", "--entitlements", ":-", str(bundle)])
    )
    entitlements.pop("com.apple.security.get-task-allow", None)
    profile = plistlib.loads(run(["security", "cms", "-D", "-i", str(profile_path)]))
    validate_profile(profile, identifier, certificate, entitlements)
    shutil.copyfile(profile_path, bundle / "Contents/embedded.provisionprofile")
    path = directory / f"{identifier}.entitlements"
    path.write_bytes(plistlib.dumps(entitlements))
    run(
        [
            "codesign",
            "--force",
            "--options",
            "runtime",
            "--timestamp",
            "--sign",
            certificate,
            "--keychain",
            keychain,
            "--entitlements",
            str(path),
            str(bundle),
        ],
        timeout=60,
    )


def package_archive(options, application, installer, keychain, directory):
    """Sign inside out and construct a local installer without contacting App Store Connect."""
    options.output.mkdir(parents=True)
    app = options.output / "SpamWise.app"
    source = options.archive / "Products/Applications/SpamWise.app"
    run(["ditto", str(source), str(app)])
    if (app / "Contents/Frameworks").exists() or (
        app / "Contents/XPCServices"
    ).exists():
        raise ValueError(
            "Additional nested code requires an explicit signing inventory"
        )
    extension = app / "Contents/PlugIns/MailExtension.appex"
    if set((app / "Contents/PlugIns").iterdir()) != {extension}:
        raise ValueError("Unexpected nested extension")
    sign_bundle(
        extension,
        options.extension_profile,
        "codes.tim.SpamWise.MailExtension",
        application,
        keychain,
        directory,
    )
    sign_bundle(
        app, options.app_profile, "codes.tim.SpamWise", application, keychain, directory
    )
    run(["codesign", "--verify", "--deep", "--strict", str(app)])
    package = options.output / "SpamWise.pkg"
    run(
        [
            "productbuild",
            "--component",
            str(app),
            "/Applications",
            "--sign",
            installer,
            "--keychain",
            keychain,
            "--timestamp",
            str(package),
        ],
        timeout=90,
    )
    (options.output / "package-signature.txt").write_bytes(
        run(["pkgutil", "--check-signature", str(package)])
    )


def main():
    """Use existing profiles and keys for local export; never upload or change portal state."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--certificates", required=True, type=Path)
    parser.add_argument("--env-file", required=True, type=Path)
    parser.add_argument("--archive", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--app-profile", required=True, type=Path)
    parser.add_argument("--extension-profile", required=True, type=Path)
    options = parser.parse_args()
    if not options.archive.is_dir() or options.output.exists():
        raise ValueError("Use an existing signed archive and a new output directory")
    helpers = runpy.run_path(str(Path(__file__).with_name("notarize-match.py")))
    environment = os.environ.copy()
    environment["MATCH_PASSWORD"] = helpers["match_password"](options.env_file)
    previous_umask = os.umask(0o077)
    try:
        with tempfile.TemporaryDirectory(prefix="SpamWise-store-signing-") as name:
            directory = Path(name)
            with temporary_keychain(directory) as (keychain, password):
                application = import_identity(
                    options.certificates,
                    "distribution",
                    directory,
                    keychain,
                    environment,
                )
                installer = import_identity(
                    options.certificates,
                    "mac_installer_distribution",
                    directory,
                    keychain,
                    environment,
                )
                run(
                    [
                        "security",
                        "set-key-partition-list",
                        "-S",
                        "apple-tool:,apple:,codesign:",
                        "-s",
                        "-k",
                        password,
                        keychain,
                    ]
                )
                package_archive(options, application, installer, keychain, directory)
    finally:
        os.umask(previous_umask)
    print(
        "Local App Store export completed; temporary signing material removed. Nothing uploaded."
    )


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        raise SystemExit(
            "Local packaging interrupted; temporary signing material removed"
        ) from None
    except (
        OSError,
        ValueError,
        KeyError,
        RuntimeError,
        subprocess.TimeoutExpired,
    ) as error:
        if isinstance(error, subprocess.TimeoutExpired):
            raise SystemExit("Local export timed out; no success claimed") from None
        raise SystemExit(str(error)) from None
