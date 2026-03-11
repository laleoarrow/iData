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
  echo "Signing $target"
  codesign \
    --force \
    --sign "$IDENTITY" \
    --timestamp \
    --options runtime \
    "$target"
}

while IFS= read -r target; do
  [[ -n "$target" ]] || continue
  sign_target "$target"
done < <(
  python3 - "$APP_PATH" <<'PY'
import os
import sys

app_path = sys.argv[1]
frameworks = os.path.join(app_path, "Contents", "Frameworks")
if not os.path.isdir(frameworks):
    sys.exit(0)

targets = []
for dirpath, dirnames, _ in os.walk(frameworks, followlinks=False):
    for dirname in dirnames:
        if dirname.endswith((".app", ".framework", ".xpc", ".bundle")):
            targets.append(os.path.join(dirpath, dirname))

seen = set()
for path in sorted(targets, key=lambda item: (item.count(os.sep), item), reverse=True):
    real = os.path.realpath(path)
    if real in seen:
        continue
    seen.add(real)
    print(path)
PY
)

sign_target "$APP_PATH"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
echo "Signed $APP_PATH"
