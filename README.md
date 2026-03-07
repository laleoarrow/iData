# iData

[![Build](https://img.shields.io/github/actions/workflow/status/laleoarrow/iData/swift.yml?branch=main&style=flat-square)](https://github.com/laleoarrow/iData/actions/workflows/swift.yml)
[![Release](https://img.shields.io/github/v/release/laleoarrow/iData?style=flat-square)](https://github.com/laleoarrow/iData/releases)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-111111?style=flat-square)](https://github.com/laleoarrow/iData)

`iData` is a native macOS shell around `VisiData`.

## What it does today

- opens files through a native macOS window
- embeds the `VisiData` session inside the app window
- remembers recent files
- supports drag-and-drop and Finder opening
- lets you configure the `vd` executable path
- packages a standalone `iData.app`

## Dependency

`iData` does not bundle `VisiData`.

Recommended install:

```bash
brew install visidata
```

If you use a custom install, set the `vd` executable path in Preferences.

## Supported formats

- `csv`
- `tsv`
- `txt`
- `json`
- `jsonl`
- `xlsx`
- `csv.gz`
- `tsv.gz`
- `txt.gz`

## Development

Run tests:

```bash
swift test
/bin/zsh -lc 'xcodebuild -project iData.xcodeproj -scheme iDataApp -configuration Debug -derivedDataPath .build/xcode-debug build'
```

Build the app bundle:

```bash
./scripts/build_app.sh
```

Package a GitHub release asset:

```bash
./scripts/package_release.sh 0.1.0
```

Install locally:

- Copy `dist/iData.app` into `/Applications`
- Quit any other running `iData` instance before testing the release build
