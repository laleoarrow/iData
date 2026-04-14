# Debugging iData

## Fast verification

```bash
cd /Users/leoarrow/Project/mypackage/agents/iData
swift build
swift test
/bin/zsh -lc 'xcodebuild -project iData.xcodeproj -scheme iDataApp -configuration Debug -derivedDataPath .build/xcode-debug build'
./scripts/build_app.sh
```

This matches the local equivalent of `.github/workflows/swift.yml`.

## Required handoff after any code change

Before claiming a fix or feature is ready, complete this checklist against the final diff, not an earlier draft:

1. Run the full local equivalent of `.github/workflows/swift.yml`:

```bash
cd /Users/leoarrow/Project/mypackage/agents/iData
swift build -v
swift test -v
xcodebuild -project iData.xcodeproj -scheme iDataApp -configuration Debug -derivedDataPath .build/xcode-debug build
./scripts/build_app.sh
```

2. If the change touches packaging, release assets, update metadata, `docs/appcast.xml`, or Homebrew sync behavior, inspect the impacted workflow file under `.github/workflows/` and verify the new assumptions still match the automation. For release automation changes, this includes `.github/workflows/sync-homebrew-cask.yml`.
3. Replace `/Applications/iData.app` with the fresh `dist/iData.app`, launch the installed app, and leave it ready for human review unless the user explicitly says not to.
4. Run the pressure pass below against the fresh app build.
5. Remove temporary logs, debug prints, dead code, throwaway assets, and any other experiment-only artifacts before handoff.
6. Check `git status --short` before handing work off. The only remaining diff may be the intended tracked changes for review. If the task is fully finished, the worktree should otherwise be clean.

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
- "Install VisiData via Terminal" button appears on the welcome screen when executable is missing

Expected guidance:

- Users can click the "Install VisiData via Terminal" button for a one-click automated setup (`brew` or `pipx`)
- Recommended manual path:
  - `pipx install visidata`
  - `pipx inject visidata openpyxl pyxlsb xlrd zstandard`
- Optional manual path: `brew install visidata`
- Or users can set a custom executable path in Preferences

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
*Note: Closing the UI window will automatically terminate both `vd` and any descendant processes (like `gzip -dc`) via its process group.*

## Pressure pass after any feature or bug fix

Run a manual stress pass against the built app before claiming the change is stable:

1. Quit every running `iData` instance, then launch the fresh `dist/iData.app` or `/Applications/iData.app`.
2. Rapidly switch between multiple files or sessions and confirm the visible table/terminal always matches the selected file.
3. Drag supported files into the window repeatedly and verify the drop target, active session, and focus state stay correct.
4. Resize the window aggressively, including narrow/wide and short/tall transitions, and watch for clipped content, tearing, stale frames, or wrong visible regions.
5. Hover and click interactive sidebar/detail controls repeatedly to catch border, glow, alignment, or hit-target regressions.
6. If the change touched terminal rendering, keep an eye on delayed layout issues: blank regions, half-painted terminal cells, or content drawn outside the expected bounds.

Record any visual defects such as:

- content not filling the available region
- stale content from a previous file/session
- hover or focus effects painting the wrong shape
- drag/drop activating the wrong target
- visible tearing, flicker, or incomplete repaint during fast changes

## Terminal frontend

`terminal.html` now retries layout/refresh for several seconds after:

- terminal open
- output writes
- focus
- resize

This is important because xterm may initially render before stable dimensions are available.
