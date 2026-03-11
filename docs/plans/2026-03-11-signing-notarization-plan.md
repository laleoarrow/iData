# Signing And Notarization Ready Release Flow Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the iData release pipeline ready for Developer ID signing and Apple notarization while keeping unsigned releases working by default.

**Architecture:** Add two small scripts for app signing and notarization, then wire them into `package_release.sh` as optional stages controlled by environment variables. Keep the current unsigned behavior as the default fallback so local packaging and CI stay usable without Apple credentials.

**Tech Stack:** zsh, macOS codesign/notarytool/stapler, Xcode build products, Sparkle appcast generation

---

### Task 1: Add the signing/notarization contract

**Files:**
- Create: `scripts/sign_app.sh`
- Create: `scripts/notarize_path.sh`
- Modify: `scripts/package_release.sh`
- Modify: `scripts/create_pkg.sh`

**Step 1: Write the failing validation first**

- Run `bash -n`/`zsh -n` against the new script stubs.
- Run the new scripts without required env vars and confirm they fail with a clear usage/config error.

**Step 2: Implement app signing**

- Add `sign_app.sh` that requires `IDATA_DEVELOPER_ID_APP`.
- Sign nested Sparkle code first, then the main app bundle.
- Verify with `codesign --verify --deep --strict --verbose=2`.

**Step 3: Implement notarization helper**

- Add `notarize_path.sh` that accepts a path and reads either:
  - `IDATA_NOTARY_KEYCHAIN_PROFILE`, or
  - `IDATA_NOTARY_KEY_PATH` + `IDATA_NOTARY_KEY_ID` + `IDATA_NOTARY_ISSUER`
- Wait for completion and staple when the target format supports stapling.

**Step 4: Wire optional stages into release packaging**

- In `package_release.sh`, sign/staple the app before zip/dmg/pkg creation when app signing + notarization env is present.
- In `create_pkg.sh`, sign the final flat pkg when `IDATA_DEVELOPER_ID_INSTALLER` is set.
- After packaging, notarize/staple `dmg` and `pkg` when notarization is enabled.

### Task 2: Document the novice setup path

**Files:**
- Modify: `README.md`
- Modify: `.agent/release.md`
- Create: `docs/apple-signing-and-notarization.md`

**Step 1: Describe the two release modes**

- Unsigned release: current behavior, no Apple credentials needed.
- Signed/notarized release: requires Developer ID identities and notary credentials.

**Step 2: Add a novice checklist**

- Explain Apple Developer Program requirement.
- Explain `Developer ID Application` vs `Developer ID Installer`.
- Explain recommended `notarytool store-credentials` profile flow.

**Step 3: Update release commands**

- Add example commands for storing notary credentials and running `package_release.sh` with signing env vars.

### Task 3: Verify fallback and validation behavior

**Files:**
- No new files expected unless verification notes are added.

**Step 1: Syntax verification**

Run: `zsh -n scripts/sign_app.sh scripts/notarize_path.sh scripts/package_release.sh scripts/create_pkg.sh`
Expected: success

**Step 2: Missing-env validation**

Run: `./scripts/sign_app.sh dist/iData.app`
Expected: fail immediately with a clear message about `IDATA_DEVELOPER_ID_APP`

Run: `./scripts/notarize_path.sh dist/iData-v0.1.8-macos-universal.dmg`
Expected: fail immediately with a clear message about missing notary credentials

**Step 3: Unsigned release fallback**

Run: `./scripts/package_release.sh 0.1.8`
Expected: success, with explicit skip messages for signing/notarization

**Step 4: Commit**

```bash
git add scripts/sign_app.sh scripts/notarize_path.sh scripts/package_release.sh scripts/create_pkg.sh README.md .agent/release.md docs/apple-signing-and-notarization.md docs/plans/2026-03-11-signing-notarization-design.md docs/plans/2026-03-11-signing-notarization-plan.md
git commit -m "build: prepare release flow for signing and notarization"
```
