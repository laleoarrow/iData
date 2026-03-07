#!/bin/zsh
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
VERSION=${1:-0.1.3}
APP_DIR="$ROOT_DIR/dist/iData.app"
ZIP_PATH="$ROOT_DIR/dist/iData-v${VERSION}-macos-universal.zip"
DMG_PATH="$ROOT_DIR/dist/iData-v${VERSION}-macos-universal.dmg"
SHA_PATH="$ROOT_DIR/dist/SHA256SUMS.txt"
APPCAST_STAGING_DIR="$ROOT_DIR/dist/appcast"
APPCAST_PATH="$ROOT_DIR/docs/appcast.xml"
RELEASE_NOTES_SOURCE="$ROOT_DIR/docs/releases/v${VERSION}.md"
RELEASE_NOTES_STAGING="$APPCAST_STAGING_DIR/iData-v${VERSION}-macos-universal.md"
SPARKLE_BIN_DIR="$ROOT_DIR/.build/SourcePackages/artifacts/sparkle/Sparkle/bin"
GENERATE_APPCAST="$SPARKLE_BIN_DIR/generate_appcast"

"$ROOT_DIR/scripts/build_app.sh"
"$ROOT_DIR/scripts/create_dmg.sh" "$VERSION"

rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

{
  shasum -a 256 "$ZIP_PATH"
  shasum -a 256 "$DMG_PATH"
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
printf 'Created %s\n' "$SHA_PATH"
