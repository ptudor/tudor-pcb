#!/usr/bin/env python3
"""Verify a Tudor PCB release's final bytes, metadata, and optional macOS tickets."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import plistlib
import re
import stat
import subprocess
import tempfile
import uuid
import zipfile

APP_NAME = "Tudor PCB"
BUNDLE_IDENTIFIER = "net.ptudor.tudorpcb"
ASSET_PREFIX = "TudorPCB"
ARCHITECTURES = ["arm64", "x86_64"]


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as contents:
        for chunk in iter(lambda: contents.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify_checksums(directory, manifest):
    entries = {}
    for line in manifest.read_text().splitlines():
        match = re.fullmatch(r"([0-9a-f]{64})  ([A-Za-z0-9][A-Za-z0-9._-]*)", line)
        require(match is not None, "Invalid or unsafe checksum manifest entry")
        digest, name = match.groups()
        require(name not in entries, "Duplicate checksum entry: " + name)
        path = directory / name
        require(path.is_file() and not path.is_symlink(), "Missing or symlinked asset: " + name)
        require(sha256(path) == digest, "Checksum mismatch: " + name)
        entries[name] = digest
    require(bool(entries), "Empty checksum manifest")
    return entries


def read_zip(archive, name):
    entry = archive.getinfo(name)
    require(entry.file_size <= 1_048_576, "Oversized bundle metadata")
    return archive.read(entry)


def check_zip_paths(archive, root):
    entries = archive.infolist()
    require(len(entries) <= 10_000 and sum(x.file_size for x in entries) <= 512 * 1024 * 1024,
            "Oversized ZIP")
    names = set()
    for entry in entries:
        path = PurePosixPath(entry.filename)
        require(not path.is_absolute() and ".." not in path.parts and "\\" not in entry.filename,
                "Unsafe ZIP path")
        require(path.parts and path.parts[0] in (root, "__MACOSX"), "Unexpected ZIP entry")
        require(entry.filename not in names, "Duplicate ZIP entry")
        require(not stat.S_ISLNK(entry.external_attr >> 16), "Unexpected ZIP symlink")
        names.add(entry.filename)


def parse_uuids(listing):
    """Return {(uuid, architecture)} from dwarfdump --uuid output."""
    found = re.findall(r"^UUID: ([0-9A-F-]{36}) \(([a-z0-9_]+)\) ", listing, re.MULTILINE)
    require(bool(found), "No Mach-O UUIDs found")
    return set(found)


def command(*args):
    result = subprocess.run(args, check=True, capture_output=True)
    return result.stdout


def assess_app(app, metadata, notarized):
    command("codesign", "--verify", "--deep", "--strict", str(app))
    result = subprocess.run(["codesign", "-d", "--verbose=4", str(app)], check=True, capture_output=True, text=True)
    details = result.stderr + result.stdout
    require("runtime" in details, "Missing Hardened Runtime")
    if notarized:
        require("Authority=Developer ID Application:" in details, "Missing Developer ID signature")
        require("TeamIdentifier=" + metadata["team_identifier"] + "\n" in details,
                "Code signature team does not match build metadata")
        require("Timestamp=" in details, "Missing secure timestamp")
        command("xcrun", "stapler", "validate", str(app))
        command("spctl", "--assess", "--type", "execute", "--verbose=2", str(app))
    entitlements = plistlib.loads(command("codesign", "-d", "--entitlements", "-", "--xml", str(app)))
    require(entitlements.get("com.apple.security.app-sandbox") is True, "App Sandbox entitlement is missing")


def verify_macos(directory, prefix, metadata, notarized):
    with tempfile.TemporaryDirectory(prefix="tudorpcb-release-verify-") as tmp:
        extracted = Path(tmp)
        command("ditto", "-x", "-k", str(directory / (prefix + ".zip")), str(extracted))
        command("ditto", "-x", "-k", str(directory / (prefix + ".dSYM.zip")), str(extracted))
        app = extracted / (APP_NAME + ".app")
        assess_app(app, metadata, notarized)
        executable = app / "Contents/MacOS" / APP_NAME
        dsym = extracted / (APP_NAME + ".app.dSYM")
        binary_uuids = parse_uuids(command("dwarfdump", "--uuid", str(executable)).decode())
        require({arch for _, arch in binary_uuids} == set(ARCHITECTURES), "The app is not a universal binary")
        require(parse_uuids(command("dwarfdump", "--uuid", str(dsym)).decode()) == binary_uuids,
                "The dSYM does not match the shipped executable")
        dmg = directory / (prefix + ".dmg")
        command("hdiutil", "verify", str(dmg))
        if notarized:
            command("codesign", "--verify", "--strict", str(dmg))
            command("xcrun", "stapler", "validate", str(dmg))
            command("spctl", "--assess", "--type", "open", "--context", "context:primary-signature",
                    "--verbose=2", str(dmg))
        mounted = plistlib.loads(command("hdiutil", "attach", "-readonly", "-nobrowse", "-noautoopen", "-plist", str(dmg)))
        entities = mounted["system-entities"]
        device = next(x["dev-entry"] for x in entities if "dev-entry" in x)
        try:
            volume = Path(next(x["mount-point"] for x in entities if "mount-point" in x))
            disk_app = volume / (APP_NAME + ".app")
            require((volume / "Applications").is_symlink()
                    and (volume / "Applications").readlink() == Path("/Applications"),
                    "Missing Applications shortcut")
            assess_app(disk_app, metadata, notarized)
            require(json.loads((disk_app / "Contents/Resources/build-info.json").read_bytes()) == metadata,
                    "DMG and ZIP build metadata differ")
            require(sha256(disk_app / "Contents/MacOS" / APP_NAME) == sha256(executable),
                    "DMG and ZIP executables differ")
        finally:
            command("hdiutil", "detach", device)


def verify(directory, version, notarized=False, macos=False, team=None):
    require(re.fullmatch(r"\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?", version), "Invalid release version")
    prefix = ASSET_PREFIX + "-" + version + "-macos-universal"
    hashes = verify_checksums(directory, directory / "checksums.txt")
    required = [prefix + suffix for suffix in (".zip", ".dmg", ".dSYM.zip")]
    if notarized:
        required.append(prefix + ".notarization.json")
    require(set(required) <= hashes.keys(), "Release is missing required assets/checksums")
    with zipfile.ZipFile(directory / (prefix + ".zip")) as archive:
        check_zip_paths(archive, APP_NAME + ".app")
        metadata = json.loads(read_zip(archive, APP_NAME + ".app/Contents/Resources/build-info.json"))
        info = plistlib.loads(read_zip(archive, APP_NAME + ".app/Contents/Info.plist"))
        require(bool(read_zip(archive, APP_NAME + ".app/Contents/Resources/PrivacyInfo.xcprivacy")),
                "Missing privacy manifest")
        require(read_zip(archive, APP_NAME + ".app/Contents/Resources/LICENSE").startswith(b"MIT License"),
                "Missing bundled license")
    with zipfile.ZipFile(directory / (prefix + ".dSYM.zip")) as archive:
        check_zip_paths(archive, APP_NAME + ".app.dSYM")
        require(APP_NAME + ".app.dSYM/Contents/Resources/DWARF/" + APP_NAME in archive.namelist(), "Missing dSYM")
    require(metadata["version"] == version and metadata["architectures"] == ARCHITECTURES,
            "Incorrect build version or architecture")
    require(re.fullmatch(r"[0-9a-f]{40}", metadata["commit"]), "Missing source commit")
    require(type(metadata["build"]) is int and metadata["build"] > 0, "Invalid build number")
    require(info["CFBundleIdentifier"] == BUNDLE_IDENTIFIER == metadata["bundle_identifier"]
            and info["CFBundleShortVersionString"] == version.split("-", 1)[0]
            and info["CFBundleVersion"] == str(metadata["build"])
            and info["LSMinimumSystemVersion"] == metadata["minimum_system_version"],
            "Bundle identity or version differs from the build metadata")
    require(info.get("ITSAppUsesNonExemptEncryption") is False, "Missing export compliance declaration")
    if notarized:
        require(metadata["release"] is True and metadata["dirty"] is False, "Release is not a clean tagged build")
        require(re.fullmatch(r"[A-Z0-9]{10}", metadata["team_identifier"] or ""), "Invalid signing team")
        if team:
            require(metadata["team_identifier"] == team, "Unexpected signing team")
        receipt = json.loads((directory / (prefix + ".notarization.json")).read_text())
        require(receipt["schemaVersion"] == 1 and receipt["version"] == version
                and receipt["build"] == metadata["build"] and receipt["commit"] == metadata["commit"]
                and receipt["teamIdentifier"] == metadata["team_identifier"], "Notarization receipt identity mismatch")
        for kind in ("app", "dmg"):
            require(receipt[kind]["status"] == "Accepted", "Apple did not accept the " + kind)
            uuid.UUID(receipt[kind]["id"])
        receipt_names = {prefix + ".zip", prefix + ".dmg"}
        require(set(receipt["sha256"]) == receipt_names, "Notarization receipt is missing final asset hashes")
        require(all(receipt["sha256"][name] == hashes[name] for name in receipt_names),
                "Final assets differ from their notarization receipt")
    if macos:
        verify_macos(directory, prefix, metadata, notarized)
    print("Verified " + version + (" with Developer ID and notarization" if notarized else " development snapshot"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--require-notarized", action="store_true")
    parser.add_argument("--macos", action="store_true", help="Also check installed signatures, tickets, dSYM identity, and the mounted DMG")
    parser.add_argument("--team-id", help="Require a particular Developer ID team")
    args = parser.parse_args()
    try:
        verify(args.directory.resolve(), args.version, args.require_notarized, args.macos, args.team_id)
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit("Release verification failed: " + str(error)) from None


if __name__ == "__main__":
    main()
