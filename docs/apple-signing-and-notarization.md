# Apple Signing and Notarization for iData

This guide explains the future signed/notarized release path for `iData`.

## What you need first

You cannot complete this flow until you have:

1. Apple Developer Program membership
2. A `Developer ID Application` certificate installed in this Mac's Keychain
3. A `Developer ID Installer` certificate if you want the `.pkg` signed
4. Notary credentials for `xcrun notarytool`

## The two release modes

### 1. Unsigned release

Works today with no Apple credentials:

```bash
./scripts/package_release.sh 0.1.8
```

Result:

- builds `iData.app`
- creates `zip`, `dmg`, and `pkg`
- updates `docs/appcast.xml`
- prints explicit skip messages for signing/notarization

### 2. Signed and notarized release

Requires Apple credentials:

```bash
export IDATA_DEVELOPER_ID_APP="Developer ID Application: Your Name (TEAMID)"
export IDATA_DEVELOPER_ID_INSTALLER="Developer ID Installer: Your Name (TEAMID)"
export IDATA_NOTARY_KEYCHAIN_PROFILE="iData-notary"

./scripts/package_release.sh 0.1.8
```

Result:

- signs `dist/iData.app`
- notarizes the app bundle submission zip
- staples the app bundle
- builds release `zip`, `dmg`, `pkg`
- notarizes and staples the `dmg`
- notarizes and staples the `pkg` when installer signing is configured

## Recommended notary setup

Apple's recommended modern workflow is `notarytool`.

Store credentials once in Keychain:

```bash
xcrun notarytool store-credentials "iData-notary" \
  --key /absolute/path/AuthKey_XXXXXX.p8 \
  --key-id YOURKEYID \
  --issuer YOUR-ISSUER-UUID
```

Then future releases only need:

```bash
export IDATA_NOTARY_KEYCHAIN_PROFILE="iData-notary"
```

## Environment variables used by the scripts

### Signing

- `IDATA_DEVELOPER_ID_APP`
  - exact Keychain identity for app signing
- `IDATA_DEVELOPER_ID_INSTALLER`
  - exact Keychain identity for flat installer package signing

### Notarization

Preferred:

- `IDATA_NOTARY_KEYCHAIN_PROFILE`

Alternative direct API key mode:

- `IDATA_NOTARY_KEY_PATH`
- `IDATA_NOTARY_KEY_ID`
- `IDATA_NOTARY_ISSUER`

Optional:

- `IDATA_NOTARY_TIMEOUT`
  - default: `1h`

## Verification commands

Check available signing identities:

```bash
security find-identity -v -p codesigning
```

Validate a signed app bundle:

```bash
codesign --verify --deep --strict --verbose=2 dist/iData.app
```

Validate stapled tickets:

```bash
xcrun stapler validate dist/iData.app
xcrun stapler validate dist/iData-v0.1.8-macos-universal.dmg
xcrun stapler validate dist/iData-v0.1.8-macos-universal.pkg
```

## Important limitation

If these environment variables are missing, the scripts deliberately skip signing/notarization instead of guessing. That keeps local packaging usable even before Apple credentials exist.
