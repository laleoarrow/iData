# iData Tutorial 设计（2026-03-08）

## 背景

iData 已有 Help 与快捷键提示，但缺少“可跟着练”的入门流程。目标是在不改变 VisiData 核心行为的前提下，新增可视化 Tutorial，让用户基于示例数据完成一套基础操作。

参考来源：
- VisiData 官方文档（Getting Started / Navigation / Rows / Quick Reference）

## 目标

1. 在 Welcome 区域新增可见入口，一键启动 Tutorial。
2. 使用内置示例数据启动真实 `vd` 会话。
3. 在会话页面提供悬浮教练卡（floating coach），按步骤引导用户练习基础操作。
4. 保持现有 `vd` 缺失错误路径，避免“教程入口绕过依赖检查”。
5. 动画风格与现有 UI 一致，并尊重 Reduce Motion。

## 非目标

1. 不做自动按键检测或命令回放。
2. 不改动终端内核（PTY、xterm、VisiData 启动链路）。
3. 不新增网络依赖或远程教程内容。

## 方案

### 方案 A（本次落地）

- Welcome 增加 Tutorial 卡片，包含：
  - 一键启动按钮（Start Tutorial）
  - 教程步骤预览
- `AppModel` 增加 Tutorial 状态机：
  - 是否激活、当前步骤索引、步骤总数
  - 前进/后退/结束
  - 示例数据准备（内置 TSV 文本写入临时目录）
- Session 详情页增加悬浮教练层：
  - 显示当前步骤命令与说明
  - 支持 Next / Back / Finish
  - 支持收起展开
- 动画：
  - 入口卡片和悬浮层沿用现有弹簧/hover 动效
  - Reduce Motion 时降级为静态切换

### 方案 B（后续可选）

- 进一步升级为半自动任务校验（例如检测关键按键序列）。

## 数据流

1. 用户点击 Start Tutorial
2. `AppModel.startTutorial()` 生成示例 TSV 文件
3. 复用 `openExternalFile` 打开示例数据
4. Session 成功后显示 floating coach
5. 用户切换步骤；完成后结束教程状态

## 错误处理

1. `vd` 缺失：沿用当前 `LaunchError.visiDataNotFound`。
2. 示例数据写入失败：设置 `errorMessage`，不进入教程状态。
3. 会话中断：保留教程状态，但允许用户一键结束。

## 测试策略

1. `AppModelTests` 新增测试：
  - 教程步骤存在且文案完整
  - 当前步骤前进/后退边界正确
  - 结束教程会复位索引与激活状态
  - 示例数据文件生成成功且包含表头
2. 全量验证：
  - `swift test`
  - `xcodebuild ... Debug build`
  - `./scripts/build_app.sh`

## 兼容性

1. 不改变 Debug/Release bundle identifier。
2. 不修改 VisiData 启动主链路。
3. 仅在 UI 层和 `AppModel` 扩展教程行为。
