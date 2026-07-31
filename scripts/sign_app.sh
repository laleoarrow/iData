#!/bin/zsh
set -euo pipefail

APP_PATH=${1:?usage: sign_app.sh <path-to-app-bundle>}
IDENTITY=${IDATA_DEVELOPER_ID_APP:-}

if [[ -z "$IDENTITY" ]]; then
  echo "missing IDATA_DEVELOPER_ID_APP; export your 'Developer ID Application' identity name first" >&2
  exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "missing app bundle: $APP_PATH" >&2
  exit 1
fi

sign_target() {
  local target=$1
  shift
  local -a sign_arguments=(
    --force
    --sign "$IDENTITY"
  )

  if [[ "$IDENTITY" != "-" ]]; then
    sign_arguments+=(
      --timestamp
      --options runtime
    )
  fi
  sign_arguments+=("$@")

  echo "Signing $target"
  codesign "${sign_arguments[@]}" "$target"
}

SPARKLE_FRAMEWORK="$APP_PATH/Contents/Frameworks/Sparkle.framework"
SPARKLE_VERSION="$SPARKLE_FRAMEWORK/Versions/B"

if [[ -d "$SPARKLE_FRAMEWORK" ]]; then
  sign_target "$SPARKLE_VERSION/XPCServices/Installer.xpc"
  sign_target \
    "$SPARKLE_VERSION/XPCServices/Downloader.xpc" \
    --preserve-metadata=entitlements
  sign_target "$SPARKLE_VERSION/Autoupdate"
  sign_target "$SPARKLE_VERSION/Updater.app"
  sign_target "$SPARKLE_FRAMEWORK"
fi

sign_target "$APP_PATH"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
echo "Signed $APP_PATH"
