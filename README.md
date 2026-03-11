<h1 align="center">iData</h1>

<div align="center">
  <a href="https://github.com/laleoarrow/iData/actions/workflows/swift.yml">
    <img src="https://img.shields.io/badge/BUILD-PASSING-2e7d32?style=for-the-badge&logo=githubactions&logoColor=white" alt="Build Passing" />
  </a>
  <a href="https://github.com/laleoarrow/homebrew-tap/actions/workflows/tests.yml">
    <img src="https://img.shields.io/badge/BREW%20TEST--BOT-PASSING-FBB040?style=for-the-badge&logo=homebrew&logoColor=black" alt="Brew Test-Bot Passing" />
  </a>
  <a href="https://github.com/laleoarrow/iData/releases">
    <img src="https://img.shields.io/badge/RELEASE-V0.1.10-1565c0?style=for-the-badge&logo=github&logoColor=white" alt="Release V0.1.10" />
  </a>
  <a href="https://github.com/laleoarrow/iData">
    <img src="https://img.shields.io/badge/PLATFORM-macOS%2014%2B-111111?style=for-the-badge&logo=apple&logoColor=white" alt="Platform macOS 14+" />
  </a>
</div>

<div align="center">
  <a href="./README.md">English</a> | <a href="./README_zh.md">简体中文</a>
</div>


## What's iData for?
When working with very large tabular datasets, macOS surprisingly doesn’t offer many native tools that handle them gracefully. VisiData is an excellent solution—but as a command-line tool, it sometimes feels like bringing a terminal to a double-click fight.

That’s where iData comes in. Built with Swift and SwiftUI, iData provides a smooth, native macOS interface while quietly running VisiData under the hood. Instead of launching a terminal, you can simply double-click a giant table file and start exploring—a small convenience that becomes surprisingly valuable in data-heavy fields like bioinformatics.

It also supports gzipped tabular files directly, meaning you can open compressed datasets without the ritual of manual decompression. If you regularly wrestle with large data files, you probably already know how nice that feels.

## Install iData

Install with Homebrew Cask:

```bash
brew install --cask laleoarrow/tap/idata
```

Upgrade later:

```bash
brew upgrade --cask laleoarrow/tap/idata
```

`iData` does not bundle `VisiData`. Install `VisiData` separately.

Recommended install:

```bash
pipx install visidata
pipx inject visidata openpyxl
```

Optional alternative:

```bash
brew install visidata
```

Note: if you use Homebrew and need extra VisiData plugins (for example Excel loaders), install them in the same Python environment used by `vd`.

If you use a custom install path, set the `vd` executable path in Preferences.

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

- brew install path: `brew install --cask laleoarrow/tap/idata`
- release assets live on GitHub Releases
- the update feed lives at `docs/appcast.xml` and is intended for GitHub Pages hosting
- package a release with `./scripts/package_release.sh <version>`
- after a GitHub release is published, `.github/workflows/sync-homebrew-cask.yml` updates `laleoarrow/homebrew-tap` automatically when `HOMEBREW_TAP_TOKEN` is configured

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
./scripts/package_release.sh 0.1.10
```

Install locally:

- Copy `dist/iData.app` into `/Applications`
- Quit any other running `iData` instance before testing the release build
- Open `dist/iData-v0.1.10-macos-universal.dmg` if you want the drag-to-Applications installer view
- Or run `dist/iData-v0.1.10-macos-universal.pkg` for the installer package flow
