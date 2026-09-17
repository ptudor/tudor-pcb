#!/usr/bin/env python3
"""Archive, sign, notarize, and package the Tudor PCB macOS app for distribution."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import uuid

ROOT = Path(__file__).resolve().parent.parent
PROJECT_DIR = ROOT / "swift"
PROJECT = PROJECT_DIR / "TudorPCB.xcodeproj"
SCHEME = "TudorPCBMac"
APP_NAME = "Tudor PCB"
BUNDLE_IDENTIFIER = "net.ptudor.tudorpcb"
ASSET_PREFIX = "TudorPCB"
ARCHITECTURES = {"arm64", "x86_64"}


def run(*args, capture=False, cwd=ROOT):
    if capture:
        return subprocess.check_output(args, cwd=cwd, text=True).strip()
    subprocess.run(args, cwd=cwd, check=True)


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as contents:
        for chunk in iter(lambda: contents.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def base_version(project_yml):
    matches = re.findall(r'^\s*MARKETING_VERSION:\s*"?(\d+\.\d+\.\d+)"?\s*$', project_yml, re.MULTILINE)
    if len(matches) != 1:
        raise ValueError("swift/project.yml must declare one MARKETING_VERSION of the form MAJOR.MINOR.PATCH")
    return matches[0]


def developer_identity(requested, listing):
    identities = re.findall(r'\d+\)\s+([A-Fa-f0-9]{40}) "(Developer ID Application: [^"\n]+ \(([A-Z0-9]{10})\))"', listing)
    matches = [item for item in identities if requested == item[1] or requested.upper() == item[0].upper()]
    if len(matches) != 1:
        raise ValueError("Select one valid Developer ID Application identity by its exact name or SHA-1 identifier")
    identity, name, team = matches[0]
    return identity, name, team


def accepted_submission(data):
    if not isinstance(data, dict) or data.get("status") != "Accepted":
        raise ValueError("Apple did not accept the notarization submission")
    try:
        submission_id = str(uuid.UUID(data["id"]))
    except (KeyError, TypeError, ValueError, AttributeError):
        raise ValueError("Apple returned an invalid notarization submission identifier") from None
    return {"id": submission_id, "status": "Accepted"}


def export_options(team):
    """Export options for uploading the same archive to App Store Connect."""
    return {"method": "app-store-connect", "destination": "upload", "signingStyle": "automatic",
            "teamID": team, "manageAppVersionAndBuildNumber": False, "uploadSymbols": True}


def notarize(path, args):
    authentication = ["--keychain-profile", args.notary_profile]
    if args.keychain:
        authentication.extend(["--keychain", args.keychain])
    command = ["xcrun", "notarytool", "submit", str(path), *authentication,
               "--wait", "--timeout", "30m", "--output-format", "json"]
    print("Submitting " + path.name + " for Apple notarization", flush=True)
    result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True)
    log_dir = PROJECT_DIR / "build/notary-logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    log_path = log_dir / (path.name + "-" + str(uuid.uuid4()) + ".json")
    log_path.write_text(result.stdout + ("\n" + result.stderr if result.stderr else ""))
    try:
        if result.returncode:
            raise ValueError("Notarization failed or timed out")
        receipt = accepted_submission(json.loads(result.stdout))
    except (ValueError, json.JSONDecodeError) as error:
        raise SystemExit(str(error) + "; submission output: " + str(log_path)) from None
    print("Notarization accepted: " + receipt["id"], flush=True)
    return receipt


def sign(path, identity, keychain=None, entitlements=None, executable=True):
    command = ["codesign", "--force", "--sign", identity]
    if executable:
        command.extend(["--options", "runtime"])
    if entitlements:
        command.extend(["--entitlements", str(entitlements)])
    if identity != "-":
        command.append("--timestamp")
        if keychain:
            command.extend(["--keychain", keychain])
    run(*command, str(path))


def signature_details(path):
    result = subprocess.run(["codesign", "-d", "--verbose=4", str(path)], check=True, capture_output=True, text=True)
    return result.stderr + result.stdout


def zip_item(item, path):
    run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(item), str(path))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "dist")
    parser.add_argument("--version", help="Release version; defaults to a development snapshot")
    parser.add_argument("--release", action="store_true", help="Require a clean tree and a matching local version tag")
    parser.add_argument("--sign-identity", help="Developer ID Application identity name or SHA-1 identifier")
    parser.add_argument("--notary-profile", help="Validated notarytool Keychain profile")
    parser.add_argument("--keychain", help="Keychain containing both the identity and notary profile")
    parser.add_argument("--app-store-connect-key", type=Path,
                        help="App Store Connect API private key (.p8); also uploads the release archive to App Store Connect")
    parser.add_argument("--app-store-connect-key-id", help="Key identifier of the App Store Connect API key")
    parser.add_argument("--app-store-connect-issuer-id", help="Issuer identifier of the App Store Connect API key")
    args = parser.parse_args()
    if platform.system() != "Darwin":
        raise SystemExit("App packaging requires macOS and Xcode")
    if not shutil.which("xcodegen"):
        raise SystemExit("xcodegen is required to generate swift/TudorPCB.xcodeproj; see README.md")
    if not (ROOT / "LICENSE").is_file():
        raise SystemExit("LICENSE is missing; the app bundles it and public releases require it")
    try:
        base = base_version((PROJECT_DIR / "project.yml").read_text())
    except ValueError as error:
        raise SystemExit(str(error)) from None
    commit = run("git", "rev-parse", "HEAD", capture=True)
    dirty = bool(run("git", "status", "--porcelain", capture=True))
    version = args.version or base + "-dev." + commit[:7] + (".dirty" if dirty else "")
    if not re.fullmatch(r"\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?", version) or version.split("-", 1)[0] != base:
        raise SystemExit("Invalid version or version differs from MARKETING_VERSION in swift/project.yml")
    if args.release:
        if dirty or args.version is None:
            raise SystemExit("Release packaging requires a clean tree and explicit --version")
        if run("git", "rev-parse", "refs/tags/v" + version + "^{}", capture=True) != commit:
            raise SystemExit("The release tag must identify HEAD")
        if not args.sign_identity or not args.notary_profile:
            raise SystemExit("Release packaging requires --sign-identity and --notary-profile; see RELEASE.md")
    if (args.notary_profile or args.keychain) and not args.sign_identity:
        raise SystemExit("--notary-profile and --keychain require --sign-identity")
    app_store = [args.app_store_connect_key, args.app_store_connect_key_id, args.app_store_connect_issuer_id]
    if any(app_store):
        if not all(app_store) or not args.release:
            raise SystemExit("App Store Connect upload requires --release and all three --app-store-connect options")
        if not args.app_store_connect_key.is_file():
            raise SystemExit("The App Store Connect API key file does not exist")
        if not re.fullmatch(r"[A-Z0-9]{10}", args.app_store_connect_key_id):
            raise SystemExit("The App Store Connect key identifier must be 10 characters")
        try:
            uuid.UUID(args.app_store_connect_issuer_id)
        except ValueError:
            raise SystemExit("The App Store Connect issuer identifier must be a UUID") from None
    identity, identity_name, team = "-", None, None
    if args.sign_identity:
        command = ["security", "find-identity", "-v", "-p", "codesigning"]
        if args.keychain:
            command.append(args.keychain)
        try:
            identity, identity_name, team = developer_identity(args.sign_identity, run(*command, capture=True))
        except ValueError as error:
            raise SystemExit(str(error)) from None
    build_number = run("git", "rev-list", "--count", "HEAD", capture=True)
    xcode = run("xcodebuild", "-version", capture=True).replace("\n", ", ")
    run("xcodegen", "generate", cwd=PROJECT_DIR)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    prefix = ASSET_PREFIX + "-" + version + "-macos-universal"
    with tempfile.TemporaryDirectory(prefix=".tudorpcb-package-", dir=output) as tmp:
        stage = Path(tmp).resolve()
        artifacts = stage / "artifacts"
        artifacts.mkdir()
        archive = stage / "TudorPCB.xcarchive"
        settings = ["CODE_SIGN_STYLE=Manual", "CODE_SIGN_IDENTITY=" + identity, "PROVISIONING_PROFILE_SPECIFIER=",
                    "ONLY_ACTIVE_ARCH=NO", "CURRENT_PROJECT_VERSION=" + build_number]
        if args.keychain:
            settings.append("OTHER_CODE_SIGN_FLAGS=--keychain " + args.keychain)
        run("xcodebuild", "archive", "-project", str(PROJECT), "-scheme", SCHEME, "-configuration", "Release",
            "-destination", "generic/platform=macOS", "-archivePath", str(archive),
            "-derivedDataPath", str(PROJECT_DIR / "build/package"), "-quiet", *settings)
        archived = archive / "Products/Applications" / (APP_NAME + ".app")
        executable = archived / "Contents/MacOS" / APP_NAME
        info = plistlib.loads((archived / "Contents/Info.plist").read_bytes())
        if (info["CFBundleIdentifier"], info["CFBundleShortVersionString"], info["CFBundleVersion"]) != (BUNDLE_IDENTIFIER, base, build_number):
            raise SystemExit("The archived app's identity or version differs from the repository")
        actual = set(run("lipo", "-archs", str(executable), capture=True).split())
        if actual != ARCHITECTURES:
            raise SystemExit("The archived app has unexpected architectures: " + str(sorted(actual)))
        entitlements = plistlib.loads(subprocess.check_output(["codesign", "-d", "--entitlements", "-", "--xml", str(archived)]))
        if entitlements.get("com.apple.security.app-sandbox") is not True:
            raise SystemExit("The archived app must keep the App Sandbox entitlement")
        entitlements_path = stage / "entitlements.plist"
        entitlements_path.write_bytes(plistlib.dumps(entitlements))
        metadata = {"version": version, "build": int(build_number), "commit": commit, "dirty": dirty,
                    "release": args.release, "architectures": sorted(ARCHITECTURES),
                    "bundle_identifier": BUNDLE_IDENTIFIER, "minimum_system_version": info["LSMinimumSystemVersion"],
                    "xcode": xcode, "team_identifier": team}
        (archived / "Contents/Resources/build-info.json").write_text(json.dumps(metadata, indent=2) + "\n")
        shutil.copy2(ROOT / "LICENSE", archived / "Contents/Resources/LICENSE")
        sign(archived, identity, args.keychain, entitlements_path)
        run("codesign", "--verify", "--deep", "--strict", str(archived))
        details = signature_details(archived)
        if "runtime" not in details:
            raise SystemExit("The signed app lacks the Hardened Runtime flag")
        if identity != "-" and ("Authority=Developer ID Application:" not in details or "TeamIdentifier=" + team + "\n" not in details):
            raise SystemExit("The signed app does not carry the requested Developer ID signature")
        app = stage / (APP_NAME + ".app")
        run("ditto", str(archived), str(app))
        app_receipt = None
        if args.notary_profile:
            submission_zip = stage / "notary-submission.zip"
            zip_item(app, submission_zip)
            app_receipt = notarize(submission_zip, args)
            run("xcrun", "stapler", "staple", str(app))
            run("xcrun", "stapler", "validate", str(app))
            run("spctl", "--assess", "--type", "execute", "--verbose=2", str(app))
        zip_name = prefix + ".zip"
        zip_item(app, artifacts / zip_name)
        dsym = archive / "dSYMs" / (APP_NAME + ".app.dSYM")
        if not dsym.is_dir():
            raise SystemExit("The archive does not contain the app's dSYM")
        dsym_name = prefix + ".dSYM.zip"
        zip_item(dsym, artifacts / dsym_name)
        disk = stage / "disk-image"
        disk.mkdir()
        run("ditto", str(app), str(disk / (APP_NAME + ".app")))
        (disk / "Applications").symlink_to("/Applications", target_is_directory=True)
        dmg_name = prefix + ".dmg"
        dmg_path = artifacts / dmg_name
        run("hdiutil", "create", "-volname", APP_NAME + " " + version, "-srcfolder", str(disk),
            "-format", "UDZO", "-fs", "HFS+", "-ov", str(dmg_path))
        if args.sign_identity:
            sign(dmg_path, identity, args.keychain, executable=False)
        dmg_receipt = None
        if args.notary_profile:
            dmg_receipt = notarize(dmg_path, args)
            run("xcrun", "stapler", "staple", str(dmg_path))
            run("xcrun", "stapler", "validate", str(dmg_path))
            run("spctl", "--assess", "--type", "open", "--context", "context:primary-signature", "--verbose=2", str(dmg_path))
        run("hdiutil", "verify", str(dmg_path))
        names = [zip_name, dmg_name, dsym_name]
        if args.notary_profile:
            receipt_name = prefix + ".notarization.json"
            receipt = {"schemaVersion": 1, "version": version, "build": int(build_number), "commit": commit,
                       "teamIdentifier": team, "app": app_receipt, "dmg": dmg_receipt,
                       "sha256": {name: sha256(artifacts / name) for name in [zip_name, dmg_name]}}
            (artifacts / receipt_name).write_text(json.dumps(receipt, indent=2) + "\n")
            names.append(receipt_name)
        checksums = "".join(sha256(artifacts / name) + "  " + name + "\n" for name in sorted(names))
        (artifacts / "checksums.txt").write_text(checksums)
        run(sys.executable, str(ROOT / "scripts/verify-release.py"), "--directory", str(artifacts),
            "--version", version, "--macos",
            *(["--require-notarized", "--team-id", team] if args.notary_profile else []))
        app_store_dir = None
        if args.app_store_connect_key:
            # The App Store build is exported from the identical archive after the
            # direct-distribution packages pass, so both channels ship the same code.
            options_path = stage / "ExportOptions.plist"
            options_path.write_bytes(plistlib.dumps(export_options(team)))
            export_path = stage / "app-store-connect"
            print("Uploading the archive to App Store Connect", flush=True)
            run("xcodebuild", "-exportArchive", "-archivePath", str(archive), "-exportOptionsPlist", str(options_path),
                "-exportPath", str(export_path), "-allowProvisioningUpdates",
                "-authenticationKeyPath", str(args.app_store_connect_key.resolve()),
                "-authenticationKeyID", args.app_store_connect_key_id,
                "-authenticationKeyIssuerID", args.app_store_connect_issuer_id, "-quiet")
            app_store_dir = "app-store-connect-" + version
            if (output / app_store_dir).exists():
                raise SystemExit("App Store Connect upload records already exist; use a fresh --output directory")
            shutil.copytree(export_path, artifacts / app_store_dir)
        # Release destinations are immutable. Failed Apple submissions never
        # replace a previous finished package or leave a publishable manifest.
        if args.release and any((output / name).exists() for name in names + ["checksums.txt"]):
            raise SystemExit("Release assets already exist; use a fresh --output directory")
        installed = output / (APP_NAME + ".app")
        if installed.exists():
            existing = plistlib.loads((installed / "Contents/Info.plist").read_bytes())
            if existing.get("CFBundleIdentifier") != BUNDLE_IDENTIFIER:
                raise SystemExit("Refusing to replace an unrelated app in the output directory")
            shutil.rmtree(installed)
        run("ditto", str(app), str(installed))
        for name in names + ["checksums.txt"] + ([app_store_dir] if app_store_dir else []):
            os.replace(artifacts / name, output / name)
    print("Packaged " + str(installed))
    print("Developer ID signed and notarized." if args.notary_profile else
          "Development snapshot: not notarized for public distribution.")
    if app_store_dir:
        print("Uploaded to App Store Connect; records in " + str(output / app_store_dir))


if __name__ == "__main__":
    main()
