# Project overview

## Goal

`iData` is a native macOS shell for opening large tabular data with `VisiData` while preserving `VisiData` keyboard behavior.

## Current behavior

- Native macOS window with recent files, drag-and-drop, and preferences
- Embedded terminal surface inside the app window
- Launches real `vd` for supported files
- Supports:
  - `csv`
  - `tsv`
  - `txt`
  - `json`
  - `jsonl`
  - `xlsx`
  - `csv.gz`
  - `tsv.gz`
  - `txt.gz`

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
- `scripts/package_release.sh` — zip release asset generation

## Bundle identifiers

- `Debug`: `io.github.leoarrow.idata.dev`
- `Release`: `io.github.leoarrow.idata`

This avoids macOS routing file-open events for `dist/iData.app` into a running debug build.
