# Project overview

## Goal

`iData` is a native macOS shell for opening large tabular data with `VisiData` while preserving `VisiData` keyboard behavior.

## Current behavior

- Native macOS window with a welcome dashboard, recent files, drag-and-drop, and preferences
- Format Association feature: Allows users to set iData as the default app for specific file extensions in macOS, with state preserved in `UserDefaults`
- Embedded terminal surface inside the app window
- Launches real `vd` for most regular files without an extension whitelist
- Streams compressed `.gz`, `.bgz`, and `.bgzf` inputs without extracting them to disk
- Uses Sparkle 2 for update checks against a GitHub Pages `appcast.xml`

## External dependency

- `VisiData` is not bundled
- Primary iData install path for users:
  - `brew install --cask laleoarrow/tap/idata`
- Default expectation for VisiData is:
  - `pipx install visidata`
  - `pipx inject visidata openpyxl`
- Homebrew install (`brew install visidata`) is optional, but plugin/dependency guidance must remain explicit.
- iData includes a **one-click VisiData setup** from the Welcome screen if no executable is found
- Users can also point `iData` at a custom `vd` path in Preferences

## Key files

- `Sources/iData/AppModel.swift` — app state, open/reopen/drag-drop/recent handling, **format association logic (`FileTypeAssociation`)**
- `Sources/iData/ContentView.swift` — main UI, sidebar, welcome/detail panes, **FormatChip components**
- `Sources/iData/EmbeddedTerminalView.swift` — SwiftUI/AppKit bridge for the terminal host
- `Sources/iData/VisiDataSessionController.swift` — PTY session lifecycle (includes concurrency safeguards and descendant process reaping)
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
