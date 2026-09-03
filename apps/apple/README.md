# 清序 Apple 原生客户端

`apps/apple` 包含清序的 SwiftUI iOS 与 macOS 客户端。两端复用任务、番茄钟、RSS、本地存储和同步实现，不包含 Flutter 引擎。

返回：[项目首页](../../README.md) · [设计规范](../../docs/DESIGN.md) · [系统架构](../../docs/ARCHITECTURE.md) · [iOS 签名](../../docs/IOS_PRIVATE_SIGNING.md)

## 支持范围

| 目标 | 最低系统 | Scheme | 主要能力 |
| --- | --- | --- | --- |
| iOS / iPadOS | 16.2 | `QingxuiOS` | SwiftUI 主界面、RSS、WidgetKit、ActivityKit、Keychain |
| macOS | 13.0 | `QingxumacOS` | SwiftUI 桌面界面、原生设置与同步 |
| iOS 扩展 | 16.2 | `QingxuWidgets` | 主屏幕/锁屏小组件、Live Activity、灵动岛 |

## 目录

```text
Shared/         跨 Apple 平台的模型、状态、视图、存储和网络实现
iOS/            iOS 应用入口与平台桥接
macOS/          macOS 应用入口
Configuration/  entitlements、扩展 Info.plist 与权限配置
Generated/      XcodeGen 生成的 Info.plist
project.yml     XcodeGen 工程定义和版本信息
```

工程还复用 `apps/flutter/ios` 中的品牌 Assets 和 `QingxuPomodoroAttributes.swift`，保证主应用与 Widget 扩展使用同一套 ActivityAttributes 定义。这不是 Flutter iOS 客户端。

## 环境要求

- macOS 与当前稳定版 Xcode。
- XcodeGen 2.42.0 或更高版本。
- 真机运行所需的 Apple 签名身份和描述文件。

安装并生成工程：

```bash
brew install xcodegen
cd apps/apple
xcodegen generate
open QingxuApple.xcodeproj
```

`QingxuApple.xcodeproj` 是生成产物。工程设置应修改 `project.yml`，然后重新执行 `xcodegen generate`，不要只在 Xcode 图形界面中修改生成工程。

## 本地构建

无签名模拟器构建示例：

```bash
xcodebuild \
  -project QingxuApple.xcodeproj \
  -scheme QingxuiOS \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  build
```

macOS 构建：

```bash
xcodebuild \
  -project QingxuApple.xcodeproj \
  -scheme QingxumacOS \
  -configuration Debug \
  build
```

设备型号以本机 `xcrun simctl list devices available` 为准。

## 签名与系统扩展

以下标识是稳定升级与系统扩展工作的前提：

```text
主应用：one.darker.qingxu
扩展：one.darker.qingxu.widgets
App Group：group.one.darker.qingxu
```

`QingxuiOS` 依赖并嵌入 `QingxuWidgets`。真机签名时必须为两个 target 选择同一 Team，并让两份描述文件都授权 App Group。详细检查与私密云端构建见 [iOS 签名文档](../../docs/IOS_PRIVATE_SIGNING.md)。

## 数据位置

- iOS：沿用 `Documents/Qingxu` 数据目录，兼容早期客户端数据。
- macOS：`Application Support/Qingxu`。
- 同步密钥与客户端直连 AI Key：Apple Keychain。
- Widget/Live Activity 快照：App Group 共享容器；阶段标识确保专注与休息切换时不复用旧倒计时。

主题、模块开关等设备偏好不参与同步。任务、番茄钟和 RSS 阅读状态使用与 Flutter 客户端相同的协议。

## 发布

公开 `build-release.yml` 工作流会生成：

- 包含扩展但未签名的 iOS IPA。
- 未签名、未公证的 macOS ZIP 与 DMG。

`Private Signed iOS` 手动工作流用于导入个人签名材料并生成加密私有产物。证书和描述文件不得提交到本目录。

## 修改检查

提交 Apple 客户端改动前至少确认：

1. iOS 专用 API 使用 `#if os(iOS)` 或可用性检查隔离，不破坏 macOS 编译。
2. App Group 快照字段与 Widget 读取保持兼容。
3. Live Activity 使用绝对结束时间和唯一阶段标识，不依赖后台逐秒刷新；展开态显示今日目标进度。
4. `project.yml` 可以重新生成工程。
5. GitHub Actions 的 `apple-ios` 与 `apple-macos` 作业通过。
