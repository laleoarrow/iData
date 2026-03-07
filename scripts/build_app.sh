#!/bin/zsh
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
DERIVED_DATA_DIR="$ROOT_DIR/.build/xcode-release"
SOURCE_PACKAGES_DIR="$ROOT_DIR/.build/SourcePackages"
APP_DIR="$ROOT_DIR/dist/iData.app"

cd "$ROOT_DIR"

xcodebuild \
  -project "$ROOT_DIR/iData.xcodeproj" \
  -scheme iDataApp \
  -configuration Release \
  -destination 'platform=macOS' \
  -clonedSourcePackagesDirPath "$SOURCE_PACKAGES_DIR" \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  build

rm -rf "$APP_DIR"
mkdir -p "$ROOT_DIR/dist"

cp -R "$DERIVED_DATA_DIR/Build/Products/Release/iData.app" "$APP_DIR"

plutil -lint "$APP_DIR/Contents/Info.plist"
printf 'Built %s\n' "$APP_DIR"
