# iData signing and notarization design

Date: 2026-03-11

## Goal

Prepare `iData` for Apple Developer ID signing and notarization without requiring credentials to exist today. The release flow must continue producing unsigned artifacts when credentials are absent, while providing a single documented path for future signed/notarized releases.

## Constraints

- The current Mac has no valid code-signing identities.
- The current release flow already produces `zip`, `dmg`, `pkg`, and Sparkle appcast metadata.
- Future users should not have to hand-edit multiple scripts once Apple credentials exist.
- Unsigned local and CI packaging must remain functional.

## Chosen approach

Use an opt-in release pipeline driven by environment variables:

1. Build `dist/iData.app` as today.
2. If a `Developer ID Application` identity is configured, sign the app bundle inside-out.
3. If notarization credentials are configured, notarize a temporary zip of the signed app, wait for completion, and staple the app bundle.
4. Package the stapled app into release `zip`, `dmg`, and `pkg` artifacts.
5. If a `Developer ID Installer` identity is configured, sign the final flat package.
6. If notarization is enabled, notarize and staple the release `dmg` and `pkg` after packaging.

When the required credentials are absent, each optional step is skipped with an explicit log line instead of failing implicitly.

## Credential model

### Signing

- `IDATA_DEVELOPER_ID_APP`
  - value: exact `Developer ID Application: ...` identity name from Keychain
- `IDATA_DEVELOPER_ID_INSTALLER`
  - value: exact `Developer ID Installer: ...` identity name from Keychain

### Notarization

Recommended path:

- `IDATA_NOTARY_KEYCHAIN_PROFILE`
  - value: profile name created by `xcrun notarytool store-credentials`

Fallback path:

- `IDATA_NOTARY_KEY_PATH`
- `IDATA_NOTARY_KEY_ID`
- `IDATA_NOTARY_ISSUER`

## Script structure

- `scripts/sign_app.sh`
  - signs nested frameworks, XPC services, helper apps, and the main app bundle
  - verifies the final signature
- `scripts/notarize_path.sh`
  - notarizes a given archive or bundle-submission zip
  - waits for completion and optionally staples supported targets
- existing scripts updated:
  - `build_app.sh`
  - `create_pkg.sh`
  - `package_release.sh`

## Non-goals

- Automatic certificate creation
- Automatic Keychain import/export
- App Store submission
- Mandatory failure when credentials are missing

## Verification

Minimum verification for this phase:

- shell syntax check for new/changed scripts
- `./scripts/package_release.sh 0.1.8` with no credentials still succeeds
- direct invocation of signing/notarization scripts without required env vars fails with a clear message
- existing release docs explain the novice path from “no Apple account” to “credentials ready”
