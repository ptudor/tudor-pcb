#!/usr/bin/env python3
"""Prepare an immutable draft release from verified signed CI artifacts."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess


def gh(*args):
    return subprocess.check_output(["gh", *args], text=True)


def select_release(releases, tag):
    """Return the release for `tag` from a release listing, or None.

    The "release by tag" endpoint only answers for published releases, so a
    draft created moments ago must be found through the listing instead."""
    matches = [item for item in releases if item.get("tag_name") == tag]
    if len(matches) > 1:
        raise ValueError("More than one release claims tag " + tag)
    return matches[0] if matches else None


def list_releases(repository):
    return json.loads(gh("api", "repos/" + repository + "/releases?per_page=100"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--directory", type=Path, default=Path("dist"))
    args = parser.parse_args()
    if not re.fullmatch(r"v\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?", args.tag):
        raise SystemExit("Invalid release tag")
    repository = os.environ.get("GH_REPO", "")
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise SystemExit("Set GH_REPO to the intended repository")
    version = args.tag[1:]
    spec = importlib.util.spec_from_file_location("verify_release", Path(__file__).with_name("verify-release.py"))
    verify = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(verify)
    try:
        verify.verify(args.directory, version, notarized=True)
        hashes = verify.verify_checksums(args.directory, args.directory / "checksums.txt")
    except (ValueError, KeyError, OSError) as error:
        raise SystemExit("Release verification failed: " + str(error)) from None
    hashes["checksums.txt"] = verify.sha256(args.directory / "checksums.txt")
    try:
        release = select_release(list_releases(repository), args.tag)
        if release is None:
            command = ["release", "create", args.tag, "--repo", repository, "--draft", "--verify-tag",
                       "--title", "Tudor PCB " + args.tag, "--notes-file", "docs/release-notes/" + args.tag + ".md"]
            if "-" in version:
                command.append("--prerelease")
            gh(*command)
            release = select_release(list_releases(repository), args.tag)
            if release is None:
                raise SystemExit("The draft release was created but does not appear in the release listing")
    except ValueError as error:
        raise SystemExit(str(error)) from None
    if not release["draft"] or release["tag_name"] != args.tag:
        raise SystemExit("This version is already published; do not replace it")
    existing = {}
    for asset in release["assets"]:
        name = asset["name"]
        if name not in hashes or asset.get("digest") != "sha256:" + hashes[name]:
            raise SystemExit("Existing draft asset differs: " + name + "; inspect the failed run before retrying")
        existing[name] = asset
    for name in sorted(hashes.keys() - existing.keys()):
        gh("release", "upload", args.tag, str(args.directory / name), "--repo", repository)
    final = select_release(list_releases(repository), args.tag)
    if final is None or {asset["name"]: asset.get("digest") for asset in final["assets"]} != {name: "sha256:" + digest for name, digest in hashes.items()}:
        raise SystemExit("Uploaded draft assets do not match the verified bytes")
    print("Draft assets verified; ready for provenance attestation and publication")


if __name__ == "__main__":
    main()
