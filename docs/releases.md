# Builds and releases

Maintainers should follow [RELEASE.md](../RELEASE.md) for the complete repeatable
procedure: repository setup, Apple credentials, native CI, signing,
notarization, the optional Mac App Store upload, publication, and download
verification.

`scripts/package.py` generates the Xcode project with XcodeGen, archives the
`TudorPCBMac` scheme as a universal Release build, records build metadata in the
bundle, signs the app, and produces an app ZIP, an installer DMG, a dSYM ZIP,
and a SHA-256 manifest. Release runs also notarize and staple the app and DMG,
write a notarization receipt, and can upload the same archive to App Store
Connect.

## Local rehearsal

```sh
swift test --package-path swift/GerberKit
python3 scripts/test-release.py
python3 scripts/package.py
open 'dist/Tudor PCB.app'
```

`--output DIR` changes the artifact directory. Rebuilding replaces the generated
Tudor PCB artifacts in that directory; keep unrelated files elsewhere. Snapshot
names include the marketing version, source commit, and dirty-worktree status,
for example `TudorPCB-1.0.0-dev.2f150ae-macos-universal.dmg`.

The marketing version is `MARKETING_VERSION` in `swift/project.yml`. The build
number is the commit count of `HEAD`. Each app includes
`Contents/Resources/build-info.json` with the package version, build number,
commit, dirty state, architectures, minimum macOS version, Xcode version, and
signing team. Exact reproducibility across different Xcode versions is not
claimed; the attestation and metadata identify the source commit instead.

Packaging checks the architecture slices, the App Sandbox entitlements, the
Hardened Runtime flag, the code signature, the dSYM's Mach-O UUIDs against the
shipped executable, the DMG's contents, and the checksum manifest.

## App installation and signing

Open the DMG and drag **Tudor PCB.app** to its Applications shortcut, or expand
the app ZIP in Finder and move the app into Applications. The app requires
macOS 14 or later and runs natively on Apple silicon and Intel Macs.

Local snapshots use ad hoc signatures and open only on the Mac that built them
or after an explicit Gatekeeper override; they are not for distribution. Public
release packaging requires a Developer ID Application identity and a validated
notarization profile. It signs the app with Hardened Runtime and a secure
timestamp, requires Apple to accept both the app and the DMG, staples and
validates both tickets, and checks Gatekeeper acceptance before publishing.
There is no unsigned fallback for `--release`.

Final asset hashes and accepted submission IDs are recorded in the release's
`.notarization.json` receipt. See the
[credential setup and signed rehearsal](../RELEASE.md#configure-apple-credentials).

## GitHub automation

| Trigger | Checks and artifacts |
| --- | --- |
| Push to `main`, pull request, or manual CI | Release-script tests and workflow lint; GerberKit and app tests plus snapshot packaging on Apple silicon and Intel macOS; downloadable snapshot artifacts |
| Weekly or source changes | Redacted secret scan of Git history; Dependabot updates for pinned actions |
| Push a version tag | Required CI and secret scan; a signed, notarized universal package; optional App Store Connect upload; draft, provenance attestation, and publication |

Actions are pinned to commits, checkout does not retain credentials, and only
the release job has publishing permissions. Signed packages are built from the
checked tag and verified with their final signatures before being uploaded. The
publishing job consumes those exact artifacts.

The release begins as a draft. If attestation fails, it stays a draft.
Investigate the failed run before publishing manually. Correct a published
artifact using a new version; do not overwrite an existing public version tag.

## Verify a download

Download an asset and `checksums.txt` from the same release. Compute its SHA-256
and compare it with the manifest:

```sh
shasum -a 256 TudorPCB-1.0.0-macos-universal.dmg
```

When every listed asset is present, `shasum -a 256 -c checksums.txt` checks the
whole manifest. A checksum detects changed bytes; provenance requires verifying
the attestation and its expected source commit. With a recent GitHub CLI:

```sh
gh attestation verify TudorPCB-1.0.0-macos-universal.dmg --repo ptudor/tudor-pcb \
  --signer-workflow ptudor/tudor-pcb/.github/workflows/release.yml
```

Inspect the verified repository, workflow, tag, and commit. Development
snapshots are not release-attested. GitHub attestations establish build
provenance and do not substitute for Apple code signing or notarization. See
[GitHub's attestation documentation](https://github.com/actions/attest).
