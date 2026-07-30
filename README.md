<h1 align="center">iData</h1>

<div align="center">
  <a href="https://github.com/laleoarrow/iData/actions/workflows/swift.yml">
    <img src="https://github.com/laleoarrow/iData/actions/workflows/swift.yml/badge.svg?branch=main" alt="Swift build and tests" />
  </a>
  <a href="https://github.com/laleoarrow/homebrew-tap/actions/workflows/tests.yml">
    <img src="https://github.com/laleoarrow/homebrew-tap/actions/workflows/tests.yml/badge.svg" alt="Homebrew tests" />
  </a>
  <a href="https://github.com/laleoarrow/iData/releases/latest">
    <img src="https://img.shields.io/github/v/release/laleoarrow/iData?style=flat&amp;logo=github&amp;label=release" alt="Latest release" />
  </a>
  <img src="https://img.shields.io/badge/macOS-14%2B-111111?style=flat&amp;logo=apple" alt="macOS 14 or newer" />
</div>

<div align="center">
  <a href="./README.md">English</a> | <a href="./README_zh.md">简体中文</a>
</div>

## What iData is

iData is a lightweight, native **macOS 14+** front end for
[VisiData](https://www.visidata.org/). It lets you open a large table from
Finder and work with it through an embedded terminal while preserving
VisiData's commands, shortcuts, and loaders.

**VisiData is an external dependency and is not bundled with iData.** If iData
cannot find `vd`, it stays on the welcome screen and shows installation
guidance instead of opening an empty terminal. A nonstandard `vd` executable
can be selected in **Preferences > VisiData Runtime**.

## Install

### 1. Install iData

```bash
brew install --cask laleoarrow/tap/idata
```

Upgrade later with:

```bash
brew upgrade --cask laleoarrow/tap/idata
```

### 2. Install VisiData

The recommended setup keeps VisiData and common optional loaders in one
isolated environment:

```bash
pipx install visidata
pipx inject visidata openpyxl pyxlsb xlrd zstandard
```

Homebrew is also supported:

```bash
brew install visidata
```

If a Homebrew installation needs extra loaders, install them in the same
Python environment used by `vd`.

## File handling

Files selected with iData's **Open** command go directly to VisiData. For files
sent to iData by Finder, uncompressed files up to 100 MiB are handed to a
preferred desktop app (WPS Office, then Microsoft Excel by default); larger
files open in iData. This handoff app is configurable in Preferences.

Gzip-like inputs (`.gz`, `.bgz`, and `.bgzf`) always stay in iData: their
decompressed bytes are streamed to VisiData without creating an extracted
copy.

Common examples include `csv`, `tsv`, `json`, `jsonl`, `xlsx`, `ma`,
`bed.bgz`, `csv.gz`, and files with uncommon suffixes.

## Updates

iData uses Sparkle 2 for in-app updates.

- Release assets are published on [GitHub Releases](https://github.com/laleoarrow/iData/releases).
- The update feed is stored at `docs/appcast.xml` for GitHub Pages hosting.
- A published GitHub release can trigger `.github/workflows/sync-homebrew-cask.yml`
  to update `laleoarrow/homebrew-tap` when `HOMEBREW_TAP_TOKEN` is configured.

## Development

Run the test and Debug-build checks:

```bash
swift test
xcodebuild -project iData.xcodeproj -scheme iDataApp -configuration Debug \
  -clonedSourcePackagesDirPath .build/SourcePackages \
  -derivedDataPath .build/xcode-debug build
```

Build the installable app:

```bash
./scripts/build_app.sh
```

Package release assets:

```bash
./scripts/package_release.sh <version>
```

The app bundle is written to `dist/iData.app`; packaged installers use names
such as `dist/iData-v<version>-macos-universal.dmg` and
`dist/iData-v<version>-macos-universal.pkg`.
