#!/bin/zsh
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
VERSION=${1:-0.1.0}
APP_DIR="$ROOT_DIR/dist/iData.app"
ZIP_PATH="$ROOT_DIR/dist/iData-v${VERSION}-macos-universal.zip"
SHA_PATH="$ROOT_DIR/dist/SHA256SUMS.txt"

"$ROOT_DIR/scripts/build_app.sh"

rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

shasum -a 256 "$ZIP_PATH" > "$SHA_PATH"

printf 'Created %s\n' "$ZIP_PATH"
printf 'Created %s\n' "$SHA_PATH"
