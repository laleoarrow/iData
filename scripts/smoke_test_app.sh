#!/bin/zsh
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
APP_PATH=${1:-"$ROOT_DIR/dist/iData.app"}
LAUNCHED_PID=""
EXPECTED_EXECUTABLE=""
SMOKE_TOKEN="idata-smoke-$(uuidgen)"

smoke_process_is_running() {
  local process_command

  [[ -n "$LAUNCHED_PID" ]] || return 1
  kill -0 "$LAUNCHED_PID" 2>/dev/null || return 1

  process_command=$(ps -p "$LAUNCHED_PID" -o command= | sed -e 's/^[[:space:]]*//')
  [[ "$process_command" == "$EXPECTED_EXECUTABLE"* ]] || return 1
  [[ "$process_command" == *"$SMOKE_TOKEN"* ]]
}

cleanup() {
  smoke_process_is_running || return

  kill -TERM "$LAUNCHED_PID" 2>/dev/null || return
  for _ in {1..30}; do
    kill -0 "$LAUNCHED_PID" 2>/dev/null || return
    sleep 0.1
  done

  smoke_process_is_running || return
  kill -KILL "$LAUNCHED_PID" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ ! -d "$APP_PATH" ]]; then
  echo "missing app bundle: $APP_PATH" >&2
  exit 1
fi

EXECUTABLE_NAME=$(plutil -extract CFBundleExecutable raw "$APP_PATH/Contents/Info.plist")
EXPECTED_EXECUTABLE=$(cd "$APP_PATH/Contents/MacOS" && pwd -P)/$EXECUTABLE_NAME

if pgrep -x "$EXECUTABLE_NAME" >/dev/null; then
  echo "refusing to smoke test while $EXECUTABLE_NAME is already running" >&2
  exit 1
fi

open -g -j -n "$APP_PATH" --args "--$SMOKE_TOKEN"

for _ in {1..50}; do
  while IFS= read -r candidate_pid; do
    candidate_command=$(ps -p "$candidate_pid" -o command= | sed -e 's/^[[:space:]]*//')
    if [[ "$candidate_command" == "$EXPECTED_EXECUTABLE"* && "$candidate_command" == *"$SMOKE_TOKEN"* ]]; then
      LAUNCHED_PID=$candidate_pid
      break
    fi
  done < <(pgrep -x "$EXECUTABLE_NAME" || true)
  [[ -n "$LAUNCHED_PID" ]] && break
  sleep 0.1
done

if [[ -z "$LAUNCHED_PID" ]]; then
  echo "$EXECUTABLE_NAME did not stay running after launch" >&2
  exit 1
fi

if ! smoke_process_is_running; then
  echo "launched process did not match the expected bundle and smoke-test token" >&2
  exit 1
fi

sleep 1
if ! smoke_process_is_running; then
  echo "$EXECUTABLE_NAME exited during the launch smoke test" >&2
  exit 1
fi

echo "Launch smoke test passed: $EXPECTED_EXECUTABLE"
