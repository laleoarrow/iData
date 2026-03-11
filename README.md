<h1 align="center">iData</h1>

<div align="center">
  <a href="https://github.com/laleoarrow/iData/actions/workflows/swift.yml">
    <img src="https://img.shields.io/github/actions/workflow/status/laleoarrow/iData/swift.yml?branch=main&style=for-the-badge" alt="Build" />
  </a>
  <a href="https://github.com/laleoarrow/iData/releases">
    <img src="https://img.shields.io/github/v/release/laleoarrow/iData?style=for-the-badge" alt="Release" />
  </a>
  <a href="https://github.com/laleoarrow/iData">
    <img src="https://img.shields.io/badge/platform-macOS%2014%2B-111111?style=for-the-badge" alt="Platform" />
  </a>
</div>

`iData` is a native macOS shell around `VisiData`.

## What it does today

- opens most regular files through a native macOS window without hardcoding suffix rules
- embeds the `VisiData` session inside the app window
- includes multi-chapter interactive tutorials with sample data, checklist progress, and an in-session floating coach (English/Chinese)
- remembers recent files
- supports drag-and-drop and Finder opening
- streams `.gz` / `.bgz` files without extracting them to disk
- checks GitHub-hosted updates through Sparkle
- lets you configure the `vd` executable path
- packages a standalone `iData.app` and drag-to-Applications `.dmg`

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
- optional Apple signing/notarization is documented in `docs/apple-signing-and-notarization.md`
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
./scripts/package_release.sh 0.1.8
```

Optional signed/notarized release after Apple credentials are ready:

```bash
export IDATA_DEVELOPER_ID_APP="Developer ID Application: Your Name (TEAMID)"
export IDATA_DEVELOPER_ID_INSTALLER="Developer ID Installer: Your Name (TEAMID)"
export IDATA_NOTARY_KEYCHAIN_PROFILE="iData-notary"

./scripts/package_release.sh 0.1.8
```

Install locally:

- Copy `dist/iData.app` into `/Applications`
- Quit any other running `iData` instance before testing the release build
- Open `dist/iData-v0.1.8-macos-universal.dmg` if you want the drag-to-Applications installer view
- Or run `dist/iData-v0.1.8-macos-universal.pkg` for the installer package flow

Signing/notarization setup guide:

- `docs/apple-signing-and-notarization.md`

## 中文说明

`iData` 是一个基于 macOS 原生界面的 `VisiData` 外壳应用，用来更方便地打开和处理大体量表格数据。

### 安装 iData（推荐）

```bash
brew install --cask laleoarrow/tap/idata
```

升级：

```bash
brew upgrade --cask laleoarrow/tap/idata
```

### 安装 VisiData（推荐）

`iData` 不内置 `VisiData`，需要你单独安装：

```bash
pipx install visidata
pipx inject visidata openpyxl
```

可选方式：

```bash
brew install visidata
```

如果你使用自定义安装路径，可以在 iData 偏好设置里指定 `vd` 可执行文件路径。

### 发布与更新

- 发布包生成：`./scripts/package_release.sh <version>`
- Homebrew 安装入口：`brew install --cask laleoarrow/tap/idata`
- 应用内更新源：`docs/appcast.xml`
