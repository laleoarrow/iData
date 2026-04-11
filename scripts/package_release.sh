#!/bin/zsh
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
VERSION=${1:-0.2.0}
APP_DIR="$ROOT_DIR/dist/iData.app"
ZIP_PATH="$ROOT_DIR/dist/iData-v${VERSION}-macos-universal.zip"
DMG_PATH="$ROOT_DIR/dist/iData-v${VERSION}-macos-universal.dmg"
PKG_PATH="$ROOT_DIR/dist/iData-v${VERSION}-macos-universal.pkg"
SHA_PATH="$ROOT_DIR/dist/SHA256SUMS.txt"
APPCAST_STAGING_DIR="$ROOT_DIR/dist/appcast"
APPCAST_PATH="$ROOT_DIR/docs/appcast.xml"
RELEASE_NOTES_SOURCE="$ROOT_DIR/docs/releases/v${VERSION}.md"
RELEASE_NOTES_STAGING="$APPCAST_STAGING_DIR/iData-v${VERSION}-macos-universal.md"
SPARKLE_BIN_DIR="$ROOT_DIR/.build/SourcePackages/artifacts/sparkle/Sparkle/bin"
GENERATE_APPCAST="$SPARKLE_BIN_DIR/generate_appcast"
APP_SIGN_IDENTITY=${IDATA_DEVELOPER_ID_APP:-}
INSTALLER_SIGN_IDENTITY=${IDATA_DEVELOPER_ID_INSTALLER:-}
NOTARY_PROFILE=${IDATA_NOTARY_KEYCHAIN_PROFILE:-}
NOTARY_KEY_PATH=${IDATA_NOTARY_KEY_PATH:-}
NOTARY_KEY_ID=${IDATA_NOTARY_KEY_ID:-}

notarization_configured() {
  [[ -n "$NOTARY_PROFILE" ]] || [[ -n "$NOTARY_KEY_PATH" && -n "$NOTARY_KEY_ID" ]]
}

"$ROOT_DIR/scripts/build_app.sh"

if [[ -n "$APP_SIGN_IDENTITY" ]]; then
  "$ROOT_DIR/scripts/sign_app.sh" "$APP_DIR"

  if notarization_configured; then
    APP_NOTARY_ZIP="$ROOT_DIR/dist/.iData-v${VERSION}-notary.zip"
    rm -f "$APP_NOTARY_ZIP"
    ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$APP_NOTARY_ZIP"
    "$ROOT_DIR/scripts/notarize_path.sh" "$APP_NOTARY_ZIP" --no-staple
    rm -f "$APP_NOTARY_ZIP"
    xcrun stapler staple -v "$APP_DIR"
    xcrun stapler validate -v "$APP_DIR"
  else
    echo "Skipping app notarization: configure IDATA_NOTARY_KEYCHAIN_PROFILE or API key env vars"
  fi
else
  echo "Skipping app signing: IDATA_DEVELOPER_ID_APP is not set"
fi

"$ROOT_DIR/scripts/create_dmg.sh" "$VERSION"
"$ROOT_DIR/scripts/create_pkg.sh" "$VERSION"

rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

if notarization_configured; then
  if [[ -n "$APP_SIGN_IDENTITY" ]]; then
    "$ROOT_DIR/scripts/notarize_path.sh" "$DMG_PATH"
  else
    echo "Skipping DMG notarization: app bundle was not Developer ID signed"
  fi

  if [[ -n "$INSTALLER_SIGN_IDENTITY" ]]; then
    "$ROOT_DIR/scripts/notarize_path.sh" "$PKG_PATH"
  else
    echo "Skipping PKG notarization: IDATA_DEVELOPER_ID_INSTALLER is not set"
  fi
else
  echo "Skipping release archive notarization: notarization credentials are not configured"
fi

{
  shasum -a 256 "$ZIP_PATH"
  shasum -a 256 "$DMG_PATH"
  shasum -a 256 "$PKG_PATH"
} > "$SHA_PATH"

if [[ -x "$GENERATE_APPCAST" ]]; then
  rm -rf "$APPCAST_STAGING_DIR"
  mkdir -p "$APPCAST_STAGING_DIR"
  cp "$ZIP_PATH" "$APPCAST_STAGING_DIR/"

  if [[ -f "$RELEASE_NOTES_SOURCE" ]]; then
    cp "$RELEASE_NOTES_SOURCE" "$RELEASE_NOTES_STAGING"
  fi

  "$GENERATE_APPCAST" \
    --embed-release-notes \
    --download-url-prefix "https://github.com/laleoarrow/iData/releases/download/v${VERSION}/" \
    --link "https://github.com/laleoarrow/iData" \
    "$APPCAST_STAGING_DIR"

  cp "$APPCAST_STAGING_DIR/appcast.xml" "$APPCAST_PATH"
  printf 'Updated %s\n' "$APPCAST_PATH"
fi

printf 'Created %s\n' "$ZIP_PATH"
printf 'Created %s\n' "$DMG_PATH"
printf 'Created %s\n' "$PKG_PATH"
printf 'Created %s\n' "$SHA_PATH"
