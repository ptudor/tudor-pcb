#!/usr/bin/env python3
"""Create or remove the release job's isolated Apple signing credentials."""
import argparse
import base64
import os
from pathlib import Path
import re
import secrets
import shlex
import shutil
import subprocess
import uuid


def run(label, *arguments):
    # Some arguments contain passwords. Never print the command, its output, or
    # a CalledProcessError that would repeat those arguments into Actions logs.
    result = subprocess.run(arguments, capture_output=True, text=True)
    if result.returncode:
        raise SystemExit("Apple credential setup failed while " + label + "; check the release environment secrets")
    return result.stdout


def decode_secret(name):
    try:
        return base64.b64decode("".join(os.environ[name].split()), validate=True)
    except ValueError:
        raise SystemExit(name + " is not valid base64") from None


def require(names):
    missing = [name for name in names if not os.environ.get(name)]
    if missing:
        raise SystemExit("Missing release environment secrets: " + ", ".join(missing) + "; see RELEASE.md")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["setup", "cleanup"])
    parser.add_argument("--app-store", action="store_true",
                        help="Also install the App Store Connect API key for uploading to the Mac App Store")
    args = parser.parse_args()
    if os.environ.get("GITHUB_ACTIONS") != "true" or not os.environ.get("RUNNER_TEMP"):
        raise SystemExit("This helper is only for GitHub Actions; use a Keychain profile locally")
    directory = Path(os.environ["RUNNER_TEMP"]).resolve() / "tudorpcb-signing"
    keychain = directory / "release.keychain-db"
    if args.action == "cleanup":
        if keychain.exists():
            result = subprocess.run(["security", "delete-keychain", str(keychain)], capture_output=True)
            if result.returncode:
                raise SystemExit("Could not remove the temporary release keychain")
        if directory.exists():
            shutil.rmtree(directory)
        return
    require(["DEVELOPER_ID_P12_BASE64", "DEVELOPER_ID_P12_PASSWORD", "APPLE_TEAM_ID",
             "NOTARY_APPLE_ID", "NOTARY_APP_PASSWORD"])
    if args.app_store:
        require(["APP_STORE_CONNECT_KEY_ID", "APP_STORE_CONNECT_ISSUER_ID", "APP_STORE_CONNECT_KEY_P8_BASE64"])
    team = os.environ["APPLE_TEAM_ID"]
    if not re.fullmatch(r"[A-Z0-9]{10}", team):
        raise SystemExit("APPLE_TEAM_ID must contain the certificate's 10-character team identifier")
    directory.mkdir(mode=0o700)
    export = directory / "identity.p12"
    export.write_bytes(decode_secret("DEVELOPER_ID_P12_BASE64"))
    export.chmod(0o600)
    password = secrets.token_urlsafe(48)
    run("creating the temporary keychain", "security", "create-keychain", "-p", password, str(keychain))
    run("setting keychain timeout", "security", "set-keychain-settings", "-lut", "7200", str(keychain))
    run("unlocking the temporary keychain", "security", "unlock-keychain", "-p", password, str(keychain))
    run("importing Developer ID", "security", "import", str(export), "-k", str(keychain),
        "-P", os.environ["DEVELOPER_ID_P12_PASSWORD"], "-T", "/usr/bin/codesign", "-T", "/usr/bin/security")
    export.unlink()
    run("granting signing-tool access", "security", "set-key-partition-list", "-S", "apple-tool:,apple:",
        "-s", "-k", password, str(keychain))
    # xcodebuild has no keychain option; it signs with identities from the user
    # search list. Keep the runner's existing keychains behind the release one.
    existing = shlex.split(run("reading the keychain search list", "security", "list-keychains", "-d", "user"))
    run("adding the release keychain to the search list", "security", "list-keychains", "-d", "user",
        "-s", str(keychain), *[item for item in existing if item != str(keychain)])
    listing = run("checking Developer ID", "security", "find-identity", "-v", "-p", "codesigning", str(keychain))
    matches = re.findall(r'\d+\)\s+([A-Fa-f0-9]{40}) "Developer ID Application: [^"\n]+ \(' + re.escape(team) + r'\)"', listing)
    if len(matches) != 1:
        raise SystemExit("The export must contain one usable Developer ID Application identity for APPLE_TEAM_ID")
    profile = "tudorpcb-release"
    run("validating notarization credentials", "xcrun", "notarytool", "store-credentials", profile,
        "--keychain", str(keychain), "--apple-id", os.environ["NOTARY_APPLE_ID"],
        "--team-id", team, "--password", os.environ["NOTARY_APP_PASSWORD"])
    variables = {"TUDORPCB_SIGN_IDENTITY": matches[0], "TUDORPCB_SIGN_KEYCHAIN": str(keychain),
                 "TUDORPCB_NOTARY_PROFILE": profile}
    if args.app_store:
        key_id = os.environ["APP_STORE_CONNECT_KEY_ID"]
        issuer = os.environ["APP_STORE_CONNECT_ISSUER_ID"]
        if not re.fullmatch(r"[A-Z0-9]{10}", key_id):
            raise SystemExit("APP_STORE_CONNECT_KEY_ID must contain the key's 10-character identifier")
        try:
            uuid.UUID(issuer)
        except ValueError:
            raise SystemExit("APP_STORE_CONNECT_ISSUER_ID must be the issuer UUID") from None
        key = decode_secret("APP_STORE_CONNECT_KEY_P8_BASE64")
        if b"-----BEGIN PRIVATE KEY-----" not in key:
            raise SystemExit("APP_STORE_CONNECT_KEY_P8_BASE64 must encode the downloaded .p8 private key")
        key_path = directory / ("AuthKey_" + key_id + ".p8")
        key_path.write_bytes(key)
        key_path.chmod(0o600)
        variables.update(TUDORPCB_ASC_KEY_PATH=str(key_path), TUDORPCB_ASC_KEY_ID=key_id, TUDORPCB_ASC_ISSUER_ID=issuer)
    with Path(os.environ["GITHUB_ENV"]).open("a") as output:
        for key, value in variables.items():
            output.write(key + "=" + value + "\n")
    print("Developer ID and notarization credentials are ready in the temporary keychain"
          + (" with the App Store Connect API key" if args.app_store else ""))


if __name__ == "__main__":
    main()
