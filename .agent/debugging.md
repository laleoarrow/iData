# Debugging iData

## Fast verification

```bash
cd /Users/leoarrow/Project/mypackage/agents/iData
swift test
/bin/zsh -lc 'xcodebuild -project iData.xcodeproj -scheme iDataApp -configuration Debug -derivedDataPath .build/xcode-debug build'
```

## Installable build

```bash
cd /Users/leoarrow/Project/mypackage/agents/iData
./scripts/build_app.sh
```

Main installable output:

- `dist/iData.app`

## Common runtime checks

### 1. `vd` missing

Symptoms:

- welcome screen stays visible and shows install guidance
- open action reports a launch error instead of showing a blank terminal

Expected guidance:

- install with `brew install visidata`
- or set a custom executable path in Preferences

### 2. Session switches but terminal content does not refresh

Check:

- `Sources/iData/EmbeddedTerminalView.swift`
- `Sources/iData/ContentView.swift`
- `iDataApp/Resources/TerminalAssets/terminal.html`

Known failure modes:

- session handoff loses terminal `ready` state
- SwiftUI reuses the same representable without rebuilding the bridge
- xterm layout does not stabilize until resize
- detail routing uses a stale `activeSession` instead of a running `displayedSession`

### 3. Wrong app instance opens files

If local testing behaves inconsistently, make sure you are not mixing:

- debug build: `.build/xcode-debug/.../iData.app`
- release build: `dist/iData.app`

Quit all running `iData` instances before retrying.

## Useful manual checks

```bash
ps -Ao pid,ppid,etime,command | egrep 'iData|vd'
```

```bash
open -a /Users/leoarrow/Project/mypackage/agents/iData/dist/iData.app /tmp/sample.csv
```

```bash
ps -Ao pid,ppid,etime,command | egrep 'iData|vd|gzip -dc'
```

## Terminal frontend

`terminal.html` now retries layout/refresh for several seconds after:

- terminal open
- output writes
- focus
- resize

This is important because xterm may initially render before stable dimensions are available.
