# iData

[![Build](https://img.shields.io/github/actions/workflow/status/laleoarrow/iData/swift.yml?branch=main&style=flat-square)](https://github.com/laleoarrow/iData/actions/workflows/swift.yml)
[![Release](https://img.shields.io/github/v/release/laleoarrow/iData?style=flat-square)](https://github.com/laleoarrow/iData/releases)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-111111?style=flat-square)](https://github.com/laleoarrow/iData)

`iData` is a native macOS shell around `VisiData`.

## What it does today

- opens most regular files through a native macOS window without hardcoding suffix rules
- embeds the `VisiData` session inside the app window
- remembers recent files
- supports drag-and-drop and Finder opening
- streams `.gz` / `.bgz` files without extracting them to disk
- checks GitHub-hosted updates through Sparkle
- lets you configure the `vd` executable path
- packages a standalone `iData.app` and drag-to-Applications `.dmg`

## Dependency

`iData` does not bundle `VisiData`.

Recommended install:

```bash
brew install visidata
```

If you use a custom install, set the `vd` executable path in Preferences.

If `VisiData` is missing, `iData` stays on the welcome screen and shows install guidance instead of opening a blank terminal pane.

## Common format examples

- `csv`
- `tsv`
- `json`
- `jsonl`
- `xlsx`
- `ma`
- `bed.bgz`
- `csv.gz`
- `tsv.gz`
- `study.any_weird_suffix`

`iData` forwards most regular files directly to `VisiData`. It only special-cases gzip-like compression (`.gz`, `.bgz`, `.bgzf`) and streams those files without extracting them.

## Updates

`iData` uses `Sparkle 2` for in-app updates.

- release assets live on GitHub Releases
- the update feed lives at `docs/appcast.xml` and is intended for GitHub Pages hosting
- package a release with `./scripts/package_release.sh <version>`

## Development

Run tests:

```bash
swift test
/bin/zsh -lc 'xcodebuild -project iData.xcodeproj -scheme iDataApp -configuration Debug -clonedSourcePackagesDirPath .build/SourcePackages -derivedDataPath .build/xcode-debug build'
```

Build the app bundle:

```bash
./scripts/build_app.sh
```

Package a GitHub release asset:

```bash
./scripts/package_release.sh 0.1.3
```

Install locally:

- Copy `dist/iData.app` into `/Applications`
- Quit any other running `iData` instance before testing the release build
- Open `dist/iData-v0.1.3-macos-universal.dmg` if you want the drag-to-Applications installer view
