#!/bin/zsh
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
VERSION=${1:?usage: package_release.sh <version>}
INFO_PLIST="$ROOT_DIR/iDataApp/Info.plist"
APP_DIR="$ROOT_DIR/dist/iData.app"
ZIP_PATH="$ROOT_DIR/dist/iData-v${VERSION}-macos-universal.zip"
DMG_PATH="$ROOT_DIR/dist/iData-v${VERSION}-macos-universal.dmg"
PKG_PATH="$ROOT_DIR/dist/iData-v${VERSION}-macos-universal.pkg"
SHA_PATH="$ROOT_DIR/dist/SHA256SUMS.txt"
APPCAST_STAGING_DIR=$(mktemp -d "${TMPDIR:-/tmp}/idata-appcast.XXXXXX")
APPCAST_PATH="$ROOT_DIR/docs/appcast.xml"
RELEASE_NOTES_SOURCE="$ROOT_DIR/docs/releases/v${VERSION}.md"
RELEASE_NOTES_STAGING="$APPCAST_STAGING_DIR/iData-v${VERSION}-macos-universal.md"
SPARKLE_BIN_DIR="$ROOT_DIR/.build/SourcePackages/artifacts/sparkle/Sparkle/bin"
GENERATE_APPCAST="$SPARKLE_BIN_DIR/generate_appcast"
SIGN_UPDATE="$SPARKLE_BIN_DIR/sign_update"
APP_SIGN_IDENTITY=${IDATA_DEVELOPER_ID_APP:-}
INSTALLER_SIGN_IDENTITY=${IDATA_DEVELOPER_ID_INSTALLER:-}
NOTARY_PROFILE=${IDATA_NOTARY_KEYCHAIN_PROFILE:-}
NOTARY_KEY_PATH=${IDATA_NOTARY_KEY_PATH:-}
NOTARY_KEY_ID=${IDATA_NOTARY_KEY_ID:-}

cleanup() {
  rm -rf "$APPCAST_STAGING_DIR"
}
trap cleanup EXIT

notarization_configured() {
  [[ -n "$NOTARY_PROFILE" ]] || [[ -n "$NOTARY_KEY_PATH" && -n "$NOTARY_KEY_ID" ]]
}

PLIST_VERSION=$(plutil -extract CFBundleShortVersionString raw "$INFO_PLIST" 2>/dev/null) || {
  echo "missing CFBundleShortVersionString in $INFO_PLIST" >&2
  exit 1
}
BUILD_NUMBER=$(plutil -extract CFBundleVersion raw "$INFO_PLIST" 2>/dev/null) || {
  echo "missing CFBundleVersion in $INFO_PLIST" >&2
  exit 1
}

if [[ "$VERSION" != "$PLIST_VERSION" ]]; then
  echo "release version $VERSION does not match CFBundleShortVersionString $PLIST_VERSION" >&2
  exit 1
fi

if [[ -z "$BUILD_NUMBER" ]]; then
  echo "CFBundleVersion must not be empty in $INFO_PLIST" >&2
  exit 1
fi

"$ROOT_DIR/scripts/build_app.sh"

BUILT_VERSION=$(plutil -extract CFBundleShortVersionString raw "$APP_DIR/Contents/Info.plist")
BUILT_BUILD_NUMBER=$(plutil -extract CFBundleVersion raw "$APP_DIR/Contents/Info.plist")
if [[ "$BUILT_VERSION" != "$VERSION" || "$BUILT_BUILD_NUMBER" != "$BUILD_NUMBER" ]]; then
  echo "built app version ${BUILT_VERSION} (${BUILT_BUILD_NUMBER}) does not match release metadata ${VERSION} (${BUILD_NUMBER})" >&2
  exit 1
fi

# build_app.sh resolves Swift package artifacts on a clean checkout, so check
# Sparkle's release tools only after that bootstrap has completed.
if [[ ! -x "$GENERATE_APPCAST" ]]; then
  echo "missing Sparkle appcast generator: $GENERATE_APPCAST" >&2
  exit 1
fi

if [[ ! -x "$SIGN_UPDATE" ]]; then
  echo "missing Sparkle update signing tool: $SIGN_UPDATE" >&2
  exit 1
fi

"$ROOT_DIR/scripts/smoke_test_app.sh" "$APP_DIR"

if [[ -n "$APP_SIGN_IDENTITY" ]]; then
  if notarization_configured; then
    APP_NOTARY_ZIP="$ROOT_DIR/dist/.iData-v${VERSION}-notary.zip"
    rm -f "$APP_NOTARY_ZIP"
    ditto -c -k --norsrc --noextattr --keepParent "$APP_DIR" "$APP_NOTARY_ZIP"
    "$ROOT_DIR/scripts/notarize_path.sh" "$APP_NOTARY_ZIP" --no-staple
    rm -f "$APP_NOTARY_ZIP"
    xcrun stapler staple -v "$APP_DIR"
    xcrun stapler validate -v "$APP_DIR"
  else
    echo "Skipping app notarization: configure IDATA_NOTARY_KEYCHAIN_PROFILE or API key env vars"
  fi
else
  echo "Using verified ad-hoc app signature: IDATA_DEVELOPER_ID_APP is not set"
fi

"$ROOT_DIR/scripts/create_dmg.sh" "$VERSION"
"$ROOT_DIR/scripts/create_pkg.sh" "$VERSION"

rm -f "$ZIP_PATH"
ditto -c -k --norsrc --noextattr --keepParent "$APP_DIR" "$ZIP_PATH"

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

(
  cd "$ROOT_DIR/dist"
  shasum -a 256 "$(basename "$ZIP_PATH")"
  shasum -a 256 "$(basename "$DMG_PATH")"
  shasum -a 256 "$(basename "$PKG_PATH")"
) > "$SHA_PATH"

cp "$ZIP_PATH" "$APPCAST_STAGING_DIR/"

if [[ -f "$RELEASE_NOTES_SOURCE" ]]; then
  cp "$RELEASE_NOTES_SOURCE" "$RELEASE_NOTES_STAGING"
fi

"$GENERATE_APPCAST" \
  --embed-release-notes \
  --download-url-prefix "https://github.com/laleoarrow/iData/releases/download/v${VERSION}/" \
  --link "https://github.com/laleoarrow/iData" \
  "$APPCAST_STAGING_DIR"

GENERATED_APPCAST="$APPCAST_STAGING_DIR/appcast.xml"
if [[ ! -f "$GENERATED_APPCAST" ]]; then
  echo "Sparkle did not generate an appcast at $GENERATED_APPCAST" >&2
  exit 1
fi

APPCAST_SIGNATURE=$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' "$GENERATED_APPCAST" | head -n1)
if [[ -z "$APPCAST_SIGNATURE" ]]; then
  echo "generated appcast is missing sparkle:edSignature" >&2
  exit 1
fi

"$SIGN_UPDATE" --verify "$ZIP_PATH" "$APPCAST_SIGNATURE"

cp "$GENERATED_APPCAST" "$APPCAST_PATH"
printf 'Updated %s\n' "$APPCAST_PATH"

printf 'Created %s\n' "$ZIP_PATH"
printf 'Created %s\n' "$DMG_PATH"
printf 'Created %s\n' "$PKG_PATH"
printf 'Created %s\n' "$SHA_PATH"
