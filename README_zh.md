<h1 align="center">iData</h1>

<div align="center">
  <a href="./README.md">English</a> | <a href="./README_zh.md">简体中文</a>
</div>

## iData 是做什么的？

如果你处理过大型数据表，大概很快就会意识到一件事：macOS 对这种事情其实并没有特别友好。几 GB 甚至几十 GB 的表格文件，很多常见工具要么直接放弃，要么开始无休止地转彩虹圈。于是你最终会遇到 VisiData——一个非常强大的工具，只不过它生活在命令行里。而很多时候，你其实只是想 双击一个文件，看看里面的数据，而不是先打开终端、输入命令、再开始工作。

于是就有了 iData。它是一个用 Swift 和 SwiftUI 写的轻量级 macOS 应用，提供原生、顺滑的界面体验，但在背后悄悄由 VisiData 驱动。换句话说，你依然拥有 VisiData 的强大能力，只是现在可以用更简单的方式触达——比如直接双击打开一个巨大的表格文件。它甚至还能直接读取 .gz 压缩的表格数据而不需要手动解压。如果你的工作环境里经常出现那种“体型惊人”的数据文件，你大概会发现：少打开一次终端、少解压一个文件，日子都会变得轻松一点。

## 安装 iData

使用 Homebrew Cask：

```bash
brew install --cask laleoarrow/tap/idata
```

升级：

```bash
brew upgrade --cask laleoarrow/tap/idata
```

## 安装 VisiData（必需）

`iData` 不内置 `VisiData`，请单独安装。

推荐方式：

```bash
pipx install visidata
pipx inject visidata openpyxl pyxlsb xlrd zstandard
```

可选方式：

```bash
brew install visidata
```

说明：如果你使用 Homebrew 且需要额外 VisiData 插件（例如 Excel 相关加载器），请确保插件安装在 `vd` 实际使用的同一 Python 环境中。

## 常见格式

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

## 发布与更新

- Homebrew 安装入口：`brew install --cask laleoarrow/tap/idata`
- Release 产物发布在 GitHub Releases
- 应用内更新源：`docs/appcast.xml`
- 发布命令：`./scripts/package_release.sh <version>`
- 发布 GitHub Release 后，`.github/workflows/sync-homebrew-cask.yml` 会自动同步 `laleoarrow/homebrew-tap`

## 开发

运行测试：

```bash
swift test
/bin/zsh -lc 'xcodebuild -project iData.xcodeproj -scheme iDataApp -configuration Debug -clonedSourcePackagesDirPath .build/SourcePackages -derivedDataPath .build/xcode-debug build'
```

构建应用：

```bash
./scripts/build_app.sh
```

打包发布：

```bash
./scripts/package_release.sh 0.1.10
```
