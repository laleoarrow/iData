#!/bin/zsh
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
VERSION=${1:?usage: create_dmg.sh <version>}
APP_NAME="iData.app"
APP_DIR="$ROOT_DIR/dist/$APP_NAME"
DMG_NAME="iData-v${VERSION}-macos-universal.dmg"
TEMP_DMG="$ROOT_DIR/dist/.iData-${VERSION}-temp.dmg"
FINAL_DMG="$ROOT_DIR/dist/$DMG_NAME"
VOLUME_NAME="Install iData"
STAGING_DIR=$(mktemp -d "${TMPDIR:-/tmp}/idata-dmg.XXXXXX")
BACKGROUND_DIR="$STAGING_DIR/.background"
BACKGROUND_PNG="$BACKGROUND_DIR/background.png"

cleanup() {
  rm -rf "$STAGING_DIR"
  rm -f "$TEMP_DMG"
}
trap cleanup EXIT

if [[ ! -d "$APP_DIR" ]]; then
  echo "missing app bundle: $APP_DIR" >&2
  exit 1
fi

mkdir -p "$BACKGROUND_DIR"
swift "$ROOT_DIR/scripts/generate_dmg_background.swift" "$BACKGROUND_PNG"

cp -R "$APP_DIR" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

SIZE_MB=$(du -sm "$STAGING_DIR" | awk '{print $1 + 80}')

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDRW \
  -size "${SIZE_MB}m" \
  "$TEMP_DMG" >/dev/null

DEVICE=$(hdiutil attach -readwrite -noverify -noautoopen "$TEMP_DMG" | awk '/^\/dev\// {print $1; exit}')
MOUNT_POINT="/Volumes/$VOLUME_NAME"

osascript <<EOF
tell application "Finder"
  tell disk "$VOLUME_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {120, 120, 920, 620}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 132
    set text size of viewOptions to 14
    set background picture of viewOptions to file ".background:background.png"
    set position of item "$APP_NAME" to {210, 265}
    set position of item "Applications" to {575, 265}
    close
    open
    update without registering applications
    delay 2
  end tell
end tell
EOF

sync
hdiutil detach "$DEVICE" >/dev/null

hdiutil convert "$TEMP_DMG" -ov -format UDZO -imagekey zlib-level=9 -o "$FINAL_DMG" >/dev/null

echo "Created $FINAL_DMG"
