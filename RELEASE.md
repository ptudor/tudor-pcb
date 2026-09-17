# Releasing Tudor PCB

This is the maintainer runbook for publishing the Tudor PCB macOS app. A public
release contains a Developer ID signed, notarized, universal (Apple silicon and
Intel) app ZIP and installer DMG, matching debug symbols, SHA-256 checksums, a
notarization receipt, and GitHub provenance attestations. The same archive can
also be uploaded to App Store Connect for the Mac App Store. Development
snapshots use ad hoc signing and are never published.

This checkout currently has no Git remote. `github` is the name used below for
the public publication remote; adding it does not change any other remote.
Publishing a version tag to GitHub starts the release workflow.

## Choose the distribution channels

| Channel | What ships | What it needs | Trade-offs |
| --- | --- | --- | --- |
| GitHub release | Notarized app ZIP and DMG, dSYM, checksums, receipt, attestations | Developer ID Application certificate, notarization credentials | Free for users, immediate, fully controlled by this repository; users install by dragging the app to Applications and receive no automatic updates |
| Mac App Store | The same archive, re-signed by Xcode with the App Store distribution identity and uploaded to App Store Connect | An app record for `net.ptudor.tudorpcb`, an App Store Connect API key, Apple review | Discoverable and updated by the App Store; Apple review adds days, pricing and availability are set in App Store Connect, and an in-app self-updater is not allowed |
| Both | Everything above from one tag | Both credential sets | One archive, one build number, one review of the code for both channels |

The app already satisfies the shared requirements: App Sandbox, Hardened
Runtime, a privacy manifest, an app category, and an export-compliance
declaration. The `release` workflow always produces the GitHub packages; the
App Store upload is switched on with a repository variable, so the decision can
change later without changing the code.

**Current decision (2026-09-16):** publish GitHub releases first. The App Store
upload stays off until an app record exists and `APP_STORE_UPLOAD` is set.

## Prerequisites

- A clean checkout of the intended commit with Xcode 26, XcodeGen, Python 3,
  and an authenticated GitHub CLI.
- A valid **Developer ID Application** certificate **and its private key**. An
  Apple Development certificate does not serve this purpose. Check with
  `security find-identity -v -p codesigning`.
- Apple notarization credentials for the certificate's team (`55QT38683G`).
- For the Mac App Store: an App Store Connect API key with the Admin role, or
  App Manager with access to cloud-managed distribution certificates, and an
  app record whose bundle identifier is `net.ptudor.tudorpcb`.
- A `LICENSE` file at the repository root. The release workflow refuses to run
  without one, and a public repository without a license grants nobody any
  rights to the source.

Apple documents certificate setup in [Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates)
and API keys in [Creating API keys for App Store Connect API](https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api).
Keep private keys, certificate exports, API keys, and passwords outside this
repository. `.gitignore` excludes `*.p12`, `*.p8`, and `*.keychain-db`.

## One-time GitHub setup

Check the account and any existing repository before creating anything:

```sh
gh auth status
gh repo view ptudor/tudor-pcb
git remote -v
```

If the repository does not exist:

```sh
gh repo create ptudor/tudor-pcb --public \
  --description 'Native SwiftUI and Metal viewer for PCB fabrication packages' \
  --disable-wiki
git remote add github https://github.com/ptudor/tudor-pcb.git
```

The commands below use GitHub CLI's credential helper for this invocation only;
they do not change the authentication setup for other remotes:

```sh
git -c credential.helper= \
  -c 'credential.https://github.com.helper=!gh auth git-credential' \
  push github main
```

Enable Actions in the repository. The workflows pin their actions to commits.
Normal CI has read-only repository access; publication alone receives write and
attestation permissions. Before the first public push, review the tree for
material that must not become public: private fabrication packages, third-party
documents whose redistribution has not been confirmed, and review evidence.
Then scan Git history:

```sh
git status --short
git ls-files
gitleaks git --redact=100 --no-banner --log-opts=--all
```

## Configure Apple credentials

Signing and notarization use different credentials. The Developer ID certificate
and private key sign the app as its publisher. Notarization sends the signed app
to Apple's service for inspection and needs an Apple account login. The App
Store upload uses a third credential, an App Store Connect API key; Xcode
signs the App Store build with a cloud-managed distribution certificate, so no
second certificate export is needed.

### Where releases are signed

The recommended choice is **GitHub Actions with credentials in the `release`
environment**: signing, notarization, publication, and the optional App Store
upload then run from a version tag without depending on this Mac being awake.

| Choice | Credential location | Work for each release |
| --- | --- | --- |
| GitHub Actions | A copy of the signing key and notary credentials is stored as encrypted environment secrets and loaded into a temporary runner keychain | Push the reviewed version tag and monitor the workflow |
| Local signing | The signing key and notary credentials stay in this Mac's Keychain | Run signed packaging here, then upload and verify the finished artifacts yourself |

Public repository visitors cannot read environment secrets. The authorized
release jobs can use them, so control over those jobs also carries control over
the signing credentials. The automated workflow implements the GitHub Actions
choice; a local-only path needs separate artifact publication and provenance
handling.

### Local packaging

A notarytool profile is a saved set of notarization credentials in Keychain. It
is not a certificate or an App Store record. Notarization credentials belong to
the team, not the app, so the `unsit-notary` profile already stored on the
release Mac serves Tudor PCB as well; confirm it with step 5 and skip the rest.
The steps below create the profile on a new Mac. Name app-specific passwords
after the place that holds them, one per Mac and one per GitHub repository, so
each can be revoked on its own.

1. Sign in to [your Apple account](https://account.apple.com/) using the account
   that belongs to the signing team.
2. Open **Sign-In and Security → App-Specific Passwords**, generate a password,
   and label it after the Mac that will hold it, for example
   `notarytool on studio Mac`. See
   [Apple's password instructions](https://support.apple.com/en-us/102654).
3. Store it, replacing the example email with that Apple account's email:

```sh
xcrun notarytool store-credentials unsit-notary \
  --apple-id 'YOUR-APPLE-ACCOUNT-EMAIL' \
  --team-id 55QT38683G
```

4. Paste the generated app-specific password at the secure prompt. Omitting the
   password from the command keeps it out of shell history.
5. Confirm that the saved profile and the identity are usable:

```sh
xcrun notarytool history --keychain-profile unsit-notary
security find-identity -v -p codesigning
```

An empty submission history is normal before the first notarization. Use the
exact Developer ID Application identity name or SHA-1 identifier from the last
command. `--keychain PATH` selects an explicit keychain for both signing and
notarization when they are stored together outside the normal search list.

### GitHub Actions

Create the `release` environment in repository settings and permit deployment
from version tags (`v*`). Store these **environment secrets**:

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64` | Base64 of a password-protected export of the Developer ID Application certificate and its private key |
| `DEVELOPER_ID_P12_PASSWORD` | Password protecting that export |
| `APPLE_TEAM_ID` | Team identifier belonging to that certificate |
| `NOTARY_APPLE_ID` | Apple account authorized to notarize for that team |
| `NOTARY_APP_PASSWORD` | An app-specific password for that account, generated for this repository and labeled `GitHub Actions tudor-pcb` |

For the Mac App Store, also store these secrets and set the repository
**variable** `APP_STORE_UPLOAD` to `true`:

| Secret | Value |
| --- | --- |
| `APP_STORE_CONNECT_KEY_ID` | Key identifier shown in App Store Connect → Users and Access → Integrations |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer identifier shown on the same page |
| `APP_STORE_CONNECT_KEY_P8_BASE64` | Base64 of the downloaded `AuthKey_KEYID.p8` file |

Enter secrets through GitHub's settings interface or `gh secret set` reading
stdin. Do not put their values in command arguments, workflow YAML, logs, or
chat. Verify names without retrieving values:

```sh
gh secret list --repo ptudor/tudor-pcb --env release
gh variable list --repo ptudor/tudor-pcb
```

`scripts/ci-signing.py` imports the certificate into an isolated temporary
keychain, adds that keychain to the search list so `xcodebuild` can sign with
it, selects the Developer ID identity for the specified team, stores a validated
notarization profile there, and with `--app-store` writes the API key to a
private file. An `always()` cleanup step deletes the keychain and credential
files. Missing credentials stop the release; there is no fallback to an ad hoc
public package.

## Prepare a version

1. Set `MARKETING_VERSION` in `swift/project.yml` to the `MAJOR.MINOR.PATCH`
   release version and write `docs/release-notes/vMAJOR.MINOR.PATCH.md`.
   Packaging refuses a version that differs from the project's marketing version.
2. The build number (`CFBundleVersion`) is the commit count of `HEAD`, so it
   rises with every commit on `main` and never needs editing. App Store Connect
   rejects a build number it has already received for the same version; a new
   upload therefore needs a new commit and tag.
3. Run the local checks and an unsigned rehearsal:

```sh
swift test --package-path swift/GerberKit
cd swift && xcodegen generate && xcodebuild test -project TudorPCB.xcodeproj \
  -scheme TudorPCBMac -destination 'platform=macOS' -quiet && cd ..
python3 scripts/test-release.py
python3 scripts/package.py
open 'dist/Tudor PCB.app'
```

Open Gerber ZIPs and extracted folders through Finder and File → Open, check a
JLCPCB review package, the color-proof gallery, the 2D inspector, and history
reopen. Use a fresh app instance so an older running copy cannot receive events.

4. Commit the complete release source and push `main` to `github`. Inspect the
   CI and Security checks on that exact commit:

```sh
gh run list --repo ptudor/tudor-pcb --branch main --limit 10
gh run view RUN_ID --repo ptudor/tudor-pcb --log-failed
```

Both `Test and package (arm64)` and `Test and package (x86_64)` must pass. The
release builds one universal package on Apple silicon; the Intel job establishes
that the same source builds, tests, and packages natively on Intel.

## Tag and publish

Check the clean tree, version, secret names, and intended commit before tagging.
Confirm that the tag does not already exist locally or on GitHub. Never move a
published version tag or overwrite its assets.

```sh
git status --short
git rev-parse HEAD
git tag --list v1.0.0
gh release view v1.0.0 --repo ptudor/tudor-pcb
git tag -a v1.0.0 -m 'Release 1.0.0'
git -c credential.helper= \
  -c 'credential.https://github.com.helper=!gh auth git-credential' \
  push github v1.0.0
gh run list --repo ptudor/tudor-pcb --workflow release.yml --limit 5
```

The absence of a release is expected before first publication. A prerelease
such as `v1.0.0-rc.1` requires matching release notes and is marked as a
prerelease on GitHub; its App Store build, if uploaded, is only useful for
TestFlight because the marketing version carries no suffix.

The release workflow performs these steps in order:

1. Validate the tag, release notes, license, and project version.
2. Run ordinary CI on both native architectures and scan full Git history.
3. Archive the tagged commit with Xcode in the `release` environment, record
   the build metadata in the bundle, and sign the app with Developer ID,
   Hardened Runtime, the App Sandbox entitlements, and a secure timestamp.
4. Submit the app ZIP to Apple with `notarytool`; require `Accepted`. Staple
   and validate the ticket and assess the app with Gatekeeper.
5. Create the downloadable app ZIP and the dSYM ZIP from the stapled app and
   its archive. Create and sign a DMG containing the same app and an
   Applications shortcut; notarize, staple, and validate it.
6. Verify signatures, tickets, the mounted DMG, dSYM identity, metadata, and
   receipts. Compute hashes only after all signing and stapling.
7. When `APP_STORE_UPLOAD` is `true`, export the identical archive with the
   `app-store-connect` method and upload it to App Store Connect. Xcode's
   distribution summary is kept as a workflow artifact.
8. Upload the finished packages, create a draft release, generate GitHub
   attestations for the exact uploaded bytes, and publish the draft only after
   those checks succeed.

Apple describes the submit/staple sequence in
[Customizing the notarization workflow](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution/customizing-the-notarization-workflow).
Signing changes bytes, and stapling can change container bytes: checksums and
GitHub asset digests must identify the final downloadable files.

## Local signed rehearsal

On the clean tagged checkout, use a fresh output directory:

```sh
python3 scripts/package.py --version 1.0.0 --release \
  --sign-identity 'Developer ID Application: YOUR NAME (TEAMID)' \
  --notary-profile unsit-notary --output dist/release-1.0.0
python3 scripts/verify-release.py --directory dist/release-1.0.0 \
  --version 1.0.0 --require-notarized --macos --team-id TEAMID
```

This submits the app and DMG to Apple. It does not publish to GitHub or upload
to App Store Connect. Adding `--app-store-connect-key AuthKey_KEYID.p8
--app-store-connect-key-id KEYID --app-store-connect-issuer-id ISSUER` uploads
the same archive to App Store Connect from this Mac. Local packages do not carry
the release workflow's build attestation; publish the artifacts produced and
checked by the workflow.

## Mac App Store

The upload only delivers a build. In App Store Connect, create the app record
before the first upload, then after processing attach the build to a version,
complete the metadata, screenshots, pricing, and availability, and submit for
review. Apple's guidance is in
[Submitting Mac apps to the App Store](https://developer.apple.com/macos/submit/).

The App Store export uses automatic signing with the API key: Xcode requests
the Mac App Store provisioning profile and a cloud-managed **Apple
Distribution** certificate for the team, so no distribution certificate is
exported to GitHub. The Developer ID signature, notarization, and DMG are not
involved in the App Store copy, and the App Store copy contains the same
`build-info.json`, version, and build number as the GitHub packages.

To distribute through the Mac App Store alone, run the local signed rehearsal
with the App Store options and do not publish the GitHub draft, or use Xcode's
Organizer on the same tagged commit. Keep the version and build-number rules
above so App Store Connect accepts the upload.

## Verify the public release

Download to an empty directory and retain the verification output:

```sh
gh release view v1.0.0 --repo ptudor/tudor-pcb
gh release download v1.0.0 --repo ptudor/tudor-pcb --dir dist/download-1.0.0
python3 scripts/verify-release.py --directory dist/download-1.0.0 \
  --version 1.0.0 --require-notarized --macos --team-id TEAMID
gh attestation verify dist/download-1.0.0/TudorPCB-1.0.0-macos-universal.dmg \
  --repo ptudor/tudor-pcb \
  --signer-workflow ptudor/tudor-pcb/.github/workflows/release.yml
```

Check the attestation's source commit and workflow, the app's version, bundle
identifier, and team, and the accepted stapled tickets. Run a quarantined
download through Finder on both an Apple silicon and an Intel Mac and open a
fabrication package. Do not disable Gatekeeper or strip quarantine to make a
release test pass.

## Failures and reruns

- **CI failure:** inspect the failed job, fix the source, commit, and rerun on
  the new commit before choosing a release tag.
- **Missing signing credentials:** configure the `release` environment; keep
  the release unpublished. Never substitute Apple Development or ad hoc signing.
- **Notary rejection or timeout:** use the recorded submission ID with
  `xcrun notarytool info` and `log`. A timeout does not cancel Apple's
  processing. Local logs remain under `swift/build/notary-logs`; do not publish
  raw account logs. No finished package is promoted from staging on a failure.
- **App Store upload failure:** read Xcode's export log in the job output. A
  rejected build number means App Store Connect already holds that number for
  the version; fix the cause, commit, and tag a new version. Rerunning the
  packaging job produces new bytes, so delete any existing draft release first.
- **Attestation failure:** the release remains a draft. Rerun the failed
  `release` job for the same tag; it verifies the existing draft assets before
  reusing them. Do not manually publish unverified files.
- **Failure after publication:** inspect the public assets. For changed code or
  bytes, issue a new version; do not silently replace files under an existing
  version.
- **Credential compromise:** revoke the affected certificate, app-specific
  password, or API key through Apple, rotate the GitHub secrets, and follow the
  provider's revocation process.

Record each execution using the tag, commit, CI and release run URLs, notary
submission receipts, asset checksums, and, when used, the App Store Connect
build number. GitHub retains the published receipts and attestations alongside
the release; keep a separate backup of credentials and release evidence.
