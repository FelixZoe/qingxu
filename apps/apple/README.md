# 清序 Apple 原生客户端

`apps/apple` 是清序的 SwiftUI iOS 与 macOS 客户端，不包含 Flutter 引擎。两端直接复用同一组 Swift 模型、本地存储与同步客户端，并与 Android、Windows 共用 `services/sync` 协议。

## 工程结构

- `Shared/`：任务、番茄钟、主题、本地存储、钥匙串和同步实现。
- `iOS/`：四标签入口、小组件/灵动岛桥接；系统支持时由原生 `TabView` 获得 Liquid Glass。
- `macOS/`：原生 `NavigationSplitView` 与 Settings 场景。
- `Configuration/`：应用组、沙盒和网络权限。
- `project.yml`：可审查、可重复生成的 XcodeGen 工程定义。

## 本地构建

```bash
brew install xcodegen
cd apps/apple
xcodegen generate
open QingxuApple.xcodeproj
```

选择 `QingxuiOS` 或 `QingxumacOS` scheme。无签名的 IPA、macOS ZIP 和 DMG 由 GitHub Actions 自动生成；iOS 真机安装仍需要用你自己的证书重新签名。

## 数据兼容

iOS 沿用原 Flutter 版本的 `Documents/Qingxu/*.json` 路径；macOS 使用 `Application Support/Qingxu`。同步字段保持不变，因此切换客户端无需迁移服务器数据。同步密钥写入系统钥匙串，配置文件不落盘保存明文密钥。
