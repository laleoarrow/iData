#!/bin/zsh
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
DERIVED_DATA_DIR="$ROOT_DIR/.build/xcode-smoke"
BUILD_LOG="$DERIVED_DATA_DIR/build.log"
EXECUTABLE_SUFFIX='Contents/MacOS/iData'

cleanup_idata_processes() {
  local pids
  pids=(${(f)"$(pgrep -x iData || true)"})
  if (( ${#pids[@]} > 0 )); then
    kill "${pids[@]}" 2>/dev/null || true
    sleep 1
  fi
}

cleanup_idata_processes

rm -rf "$DERIVED_DATA_DIR"
mkdir -p "$DERIVED_DATA_DIR"

xcodebuild \
  -project "$ROOT_DIR/iData.xcodeproj" \
  -scheme iDataApp \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  build >"$BUILD_LOG" 2>&1

APP_PATH="$DERIVED_DATA_DIR/Build/Products/Debug/iData.app"
EXECUTABLE_PATH="$APP_PATH/Contents/MacOS/iData"

open -n "$APP_PATH"
sleep 2

PID=$(pgrep -f "$EXECUTABLE_PATH" | tail -n 1 || true)
if [[ -z "$PID" ]]; then
  echo "iData did not start"
  exit 1
fi

APP_STATE=$(lsappinfo info "$PID" 2>/dev/null || true)
echo "$APP_STATE" | sed -n '1,20p'
echo "$APP_STATE" | head -n 1 | grep -F '(in front)' >/dev/null

swift -e '
import CoreGraphics
import Foundation

let pid = Int(CommandLine.arguments[1])!
let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
let matching = windows.filter { window in
    guard let ownerPID = window[kCGWindowOwnerPID as String] as? Int, ownerPID == pid else {
        return false
    }

    let isOnscreen = (window[kCGWindowIsOnscreen as String] as? Int == 1)
        || (window[kCGWindowIsOnscreen as String] as? Bool == true)

    guard isOnscreen,
          let bounds = window[kCGWindowBounds as String] as? [String: Any],
          let width = bounds["Width"] as? Double,
          let height = bounds["Height"] as? Double else {
        return false
    }

    return width > 100 && height > 100
}

if let first = matching.first {
    print(first)
    exit(EXIT_SUCCESS)
}

fputs("No visible iData window found for PID \(pid)\n", stderr)
exit(EXIT_FAILURE)
' "$PID"

cleanup_idata_processes
