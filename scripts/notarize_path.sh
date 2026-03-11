#!/bin/zsh
set -euo pipefail

TARGET_PATH=${1:?usage: notarize_path.sh <path> [--no-staple]}
STAPLE_TARGET=1

if [[ "${2:-}" == "--no-staple" ]]; then
  STAPLE_TARGET=0
fi

if [[ ! -e "$TARGET_PATH" ]]; then
  echo "missing notarization target: $TARGET_PATH" >&2
  exit 1
fi

typeset -a AUTH_ARGS
if [[ -n "${IDATA_NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
  AUTH_ARGS=(--keychain-profile "$IDATA_NOTARY_KEYCHAIN_PROFILE")
elif [[ -n "${IDATA_NOTARY_KEY_PATH:-}" && -n "${IDATA_NOTARY_KEY_ID:-}" ]]; then
  AUTH_ARGS=(--key "$IDATA_NOTARY_KEY_PATH" --key-id "$IDATA_NOTARY_KEY_ID")
  if [[ -n "${IDATA_NOTARY_ISSUER:-}" ]]; then
    AUTH_ARGS+=(--issuer "$IDATA_NOTARY_ISSUER")
  fi
else
  echo "missing notarization credentials; set IDATA_NOTARY_KEYCHAIN_PROFILE or IDATA_NOTARY_KEY_PATH + IDATA_NOTARY_KEY_ID" >&2
  exit 1
fi

TIMEOUT=${IDATA_NOTARY_TIMEOUT:-1h}

echo "Submitting $TARGET_PATH for notarization"
xcrun notarytool submit "$TARGET_PATH" "${AUTH_ARGS[@]}" --wait --timeout "$TIMEOUT"

if [[ $STAPLE_TARGET -eq 0 ]]; then
  echo "Skipping stapler for $TARGET_PATH"
  exit 0
fi

case "$TARGET_PATH" in
  *.app|*.dmg|*.pkg)
    xcrun stapler staple -v "$TARGET_PATH"
    xcrun stapler validate -v "$TARGET_PATH"
    ;;
  *)
    echo "Stapling is not supported for $TARGET_PATH; skipping"
    ;;
esac
