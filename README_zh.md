<h1 align="center">iData</h1>

<div align="center">
  <a href="./README.md">English</a>
</div>

`iData` 是一个基于 macOS 原生界面的 `VisiData` 外壳应用，用来更方便地打开和处理大体量表格数据。

## 当前能力

- 通过原生 macOS 窗口打开常见文件，不依赖硬编码后缀白名单
- 在应用窗口内嵌 `VisiData` 会话
- 提供多章节交互式教程（含示例数据、清单进度、悬浮教练，中英双语）
- 记住最近文件
- 支持拖拽与 Finder 打开
- 可流式处理 `.gz` / `.bgz` 压缩文件，无需先解压到磁盘
- 通过 Sparkle 检查 GitHub 发布更新
- 可在偏好设置中配置 `vd` 可执行文件路径
- 可打包 `iData.app` 与拖拽安装 `.dmg`

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
pipx inject visidata openpyxl
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
./scripts/package_release.sh 0.1.8
```
