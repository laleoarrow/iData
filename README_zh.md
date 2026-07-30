<h1 align="center">iData</h1>

<div align="center">
  <a href="https://github.com/laleoarrow/iData/actions/workflows/swift.yml">
    <img src="https://github.com/laleoarrow/iData/actions/workflows/swift.yml/badge.svg?branch=main" alt="Swift 构建与测试" />
  </a>
  <a href="https://github.com/laleoarrow/homebrew-tap/actions/workflows/tests.yml">
    <img src="https://github.com/laleoarrow/homebrew-tap/actions/workflows/tests.yml/badge.svg" alt="Homebrew 测试" />
  </a>
  <a href="https://github.com/laleoarrow/iData/releases/latest">
    <img src="https://img.shields.io/github/v/release/laleoarrow/iData?style=flat&amp;logo=github&amp;label=release" alt="最新版本" />
  </a>
  <img src="https://img.shields.io/badge/macOS-14%2B-111111?style=flat&amp;logo=apple" alt="macOS 14 或更高版本" />
</div>

<div align="center">
  <a href="./README.md">English</a> | <a href="./README_zh.md">简体中文</a>
</div>

## iData 是什么

iData 是 [VisiData](https://www.visidata.org/) 的轻量级原生
**macOS 14+** 前端。你可以直接从 Finder 打开大型表格，在内嵌终端中工作，
同时保留 VisiData 的命令、快捷键和数据加载能力。

**VisiData 是外部依赖，iData 不会内置它。** 如果找不到 `vd`，iData
会停留在欢迎页并显示安装指引，不会打开空白终端。若 `vd` 位于非标准位置，
可在 **偏好设置 > VisiData 运行环境** 中选择它。

## 安装

### 1. 安装 iData

```bash
brew install --cask laleoarrow/tap/idata
```

后续升级：

```bash
brew upgrade --cask laleoarrow/tap/idata
```

### 2. 安装 VisiData

推荐将 VisiData 和常用可选加载器安装在同一个隔离环境中：

```bash
pipx install visidata
pipx inject visidata openpyxl pyxlsb xlrd zstandard
```

也可以使用 Homebrew：

```bash
brew install visidata
```

如果 Homebrew 安装还需要额外加载器，请将它们装到 `vd` 实际使用的同一
Python 环境中。

## 文件处理

通过 iData 内的 **打开** 命令选择的文件会直接交给 VisiData。从 Finder
发送给 iData 的非压缩文件若不超过 100 MiB，会优先转交给桌面应用（默认先
尝试 WPS Office，再尝试 Microsoft Excel）；更大的文件会在 iData 中打开。
转交应用可在偏好设置中修改。

gzip 类输入（`.gz`、`.bgz` 和 `.bgzf`）始终留在 iData：应用会把解压后的
字节流式传给 VisiData，不生成解压副本。

常见示例包括 `csv`、`tsv`、`json`、`jsonl`、`xlsx`、`ma`、
`bed.bgz`、`csv.gz`，以及使用少见后缀的文件。

## 更新

iData 使用 Sparkle 2 提供应用内更新。

- Release 产物发布在 [GitHub Releases](https://github.com/laleoarrow/iData/releases)。
- 更新源存放在 `docs/appcast.xml`，用于 GitHub Pages 托管。
- 发布 GitHub Release 后，在已配置 `HOMEBREW_TAP_TOKEN` 时，
  `.github/workflows/sync-homebrew-cask.yml` 可自动更新
  `laleoarrow/homebrew-tap`。

## 开发

运行测试和 Debug 构建检查：

```bash
swift test
xcodebuild -project iData.xcodeproj -scheme iDataApp -configuration Debug \
  -clonedSourcePackagesDirPath .build/SourcePackages \
  -derivedDataPath .build/xcode-debug build
```

构建可安装应用：

```bash
./scripts/build_app.sh
```

打包发布产物：

```bash
./scripts/package_release.sh <version>
```

应用包会输出到 `dist/iData.app`；安装包名称类似
`dist/iData-v<version>-macos-universal.dmg` 和
`dist/iData-v<version>-macos-universal.pkg`。
