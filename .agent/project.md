# Project overview

## Goal

`iData` is a native macOS shell for opening large tabular data with `VisiData` while preserving `VisiData` keyboard behavior.

## Current behavior

- Native macOS window with a welcome dashboard, recent files, drag-and-drop, and preferences
- Embedded terminal surface inside the app window
- Launches real `vd` for most regular files without an extension whitelist
- Streams compressed `.gz`, `.bgz`, and `.bgzf` inputs without extracting them to disk
- Uses Sparkle 2 for update checks against a GitHub Pages `appcast.xml`

## External dependency

- `VisiData` is not bundled
- Default expectation is a local install such as:
  - `brew install visidata`
- Users can also point `iData` at a custom `vd` path in Preferences

## Key files

- `Sources/iData/AppModel.swift` — app state, open/reopen/drag-drop/recent handling
- `Sources/iData/ContentView.swift` — main UI, sidebar, welcome/detail panes
- `Sources/iData/EmbeddedTerminalView.swift` — SwiftUI/AppKit bridge for the terminal host
- `Sources/iData/VisiDataSessionController.swift` — PTY session lifecycle
- `iDataApp/Resources/TerminalAssets/terminal.html` — xterm frontend
- `Sources/iDataCore/TerminalCommandBuilder.swift` — regular and gzip streaming launch commands
- `Sources/iDataCore/VDExecutableLocator.swift` — `vd` discovery
- `scripts/build_app.sh` — release app build into `dist/iData.app`
- `scripts/create_dmg.sh` — drag-to-Applications installer creation
- `scripts/package_release.sh` — zip, dmg, checksums, appcast generation

## Bundle identifiers

- `Debug`: `io.github.leoarrow.idata.dev`
- `Release`: `io.github.leoarrow.idata`

This avoids macOS routing file-open events for `dist/iData.app` into a running debug build.
