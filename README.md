<p align="center">
  <img src="apps/flutter/assets/branding/qingxu-icon-master-black.png" width="112" alt="清序应用图标">
</p>

<h1 align="center">清序 Qingxu</h1>

<p align="center">本地优先、简体中文、支持自托管同步的个人任务与专注应用。</p>

<p align="center">
  <a href="https://todo.darker.one">产品预览</a> ·
  <a href="https://github.com/FelixZoe/qingxu/releases/latest">下载最新版</a> ·
  <a href="https://github.com/FelixZoe/qingxu/actions/workflows/build-release.yml">构建状态</a> ·
  <a href="docs/DEPLOYMENT.md">部署同步服务</a>
</p>

## 为什么是清序

清序把任务、专注计时和 RSS 阅读放在同一个克制的工作流里。数据先保存到设备，本地操作不依赖网络；需要跨设备时，可以把轻量同步服务部署到自己的服务器，不需要注册第三方账号。

## 主要功能

- **任务管理**：今天、可选收集箱、项目、备注、开始时间、截止时间、完成与恢复；已完成任务保留下沉并显示删除线。
- **自然日历**：周视图与月视图连续展开，日期、节日和任务列表保持在同一页面。
- **番茄钟与正计时**：自定义专注、休息、长休息和每日目标；自动切换阶段，并用年度热力图沉淀专注记录。
- **实时多端同步**：任务、番茄钟和 RSS 阅读状态自动同步；在线设备通过低占用变更通知及时刷新。
- **Apple 系统能力**：iOS 锁屏实时活动、灵动岛、主屏幕小组件和锁屏小组件；macOS 使用原生 SwiftUI。
- **原生 RSS 阅读**：来源分类、未读、收藏、搜索、OPML、离线缓存、阅读进度、正文阅读、翻译和 AI 摘要。
- **AI 助手**：RSS 摘要、原文翻译和轻量任务规划；可使用自托管代理或直接配置 OpenAI、DeepSeek 等兼容接口。
- **离线优先**：编辑先原子写入本机，服务器暂时不可用不会阻塞使用。

## 平台与下载

所有公开安装包都位于 [GitHub Releases](https://github.com/FelixZoe/qingxu/releases/latest)。

| 平台 | 实现 | Release 文件 | 说明 |
| --- | --- | --- | --- |
| iOS | SwiftUI | `Qingxu-<版本>-iOS-unsigned.ipa` | 需使用自己的 Apple 身份重新签名；包内包含 Widget/Live Activity 扩展 |
| macOS | SwiftUI | `Qingxu-<版本>-macOS-Portable.zip`、`.dmg` | 当前未公证，首次启动可能出现 Gatekeeper 提示 |
| Android | Flutter | `Qingxu-<版本>-Android.apk` | 交给 Android 系统确认安装或覆盖更新 |
| Windows | Flutter | `Qingxu-<版本>-Windows-Portable.zip`、`Windows-Setup.exe` | 提供便携版和安装版；未签名时可能出现 SmartScreen 提示 |

下载后可使用同一 Release 中的 `SHA256SUMS.txt` 校验文件完整性。安装包、校验和与构建来源证明均由 GitHub Actions 自动生成。

### 关于 iOS 自签

iOS 的灵动岛与小组件位于 `QingxuWidgets.appex`。签名工具必须同时保留并签名主应用和扩展，同时保持以下标识一致：

```text
主应用：one.darker.qingxu
扩展：one.darker.qingxu.widgets
App Group：group.one.darker.qingxu
```

仅重签主应用、删除扩展或丢失 App Group 权限，都会导致应用可以打开但灵动岛和小组件不可用。App Store 上架不是使用这些能力的必要条件；正确的扩展打包、签名和权限才是关键。详见 [iOS 私密云端签名](docs/IOS_PRIVATE_SIGNING.md)。

## 快速部署同步服务

前置条件：Linux 服务器、Docker Compose v2、一个已经启用 HTTPS 的域名。

```bash
git clone https://github.com/FelixZoe/qingxu.git
cd qingxu
cp .env.example .env
TOKEN=$(openssl rand -hex 32)
sed -i "s/^SYNC_TOKEN=.*/SYNC_TOKEN=$TOKEN/" .env
chmod 600 .env
sudo install -d -m 700 -o 65532 -g 65532 data
docker compose pull
docker compose config --quiet
docker compose up -d
curl -fsS http://127.0.0.1:8080/health
echo "$TOKEN"
```

将域名的 `/v1/` 和 `/health` 反向代理到 `http://127.0.0.1:8080`。随后在每台客户端的“设置 → 多端同步”中填写：

```text
服务器地址：https://你的域名
同步密钥：上一步生成的 64 位十六进制 TOKEN
设备名称：任意易识别名称
自动同步：开启
```

服务器地址不要附加 `/v1/sync`。更新、备份、恢复、1Panel/Nginx 配置和排障命令见 [完整部署文档](docs/DEPLOYMENT.md)。

## 数据边界

- 服务端保存任务、删除墓碑、番茄钟状态，以及 RSS 订阅、分类、已读、收藏和阅读进度。
- RSS 标题、摘要与正文由各客户端从来源获取并缓存在本机，不上传同步服务。
- 主题、界面布局等设备偏好不参与同步。
- 同步服务面向单用户、单实例；一套部署使用一个 256-bit 随机同步密钥。
- 默认数据文件为主机 `./data/store.json`，同步不能替代备份。
- AI 密钥可以只保存在服务器 `.env`；若选择客户端直连，则写入 Apple Keychain，不进入普通配置文件。

## 同步如何工作

1. 客户端先把修改写入本机，再异步上传。
2. 任务按 `id` 与 `updatedAt` 合并，删除墓碑优先，避免旧设备恢复已删除任务。
3. 番茄钟保存共享的 `endsAt`、阶段标识、每日目标与专注历史，并用响应中的 `serverTime` 校准设备时钟。
4. 前台设备通过 `/v1/changes` 等待修订号变化；只有发生变化时才拉取完整状态。
5. 5 分钟完整同步仅用于断线容错，不进行高频全量轮询。

协议细节见 [同步协议 v1](docs/SYNC_PROTOCOL.md)。

## 项目结构

```text
apps/apple/          SwiftUI iOS / macOS 客户端与 XcodeGen 工程定义
apps/flutter/        Flutter Android / Windows 客户端
services/sync/       Go 同步与可选 AI 代理服务
scripts/ios/         iOS 扩展与签名辅助脚本
scripts/windows/     Windows 安装包配置
docs/                产品、架构、协议、部署与签名文档
.github/workflows/   测试、四端构建、Docker 和自动 Release
```

`todo.darker.one` 是介绍、预览和下载入口，不是浏览器版任务客户端；站点源码与本仓库分离。

## 开发

### Android / Windows

```bash
cd apps/flutter
flutter pub get
flutter analyze
flutter test
flutter run -d windows   # 或使用已连接的 Android 设备
```

### iOS / macOS

需要 macOS、Xcode 和 XcodeGen：

```bash
brew install xcodegen
cd apps/apple
xcodegen generate
open QingxuApple.xcodeproj
```

选择 `QingxuiOS` 或 `QingxumacOS` scheme。真机运行需要在本地配置自己的签名身份和描述文件。

### 同步服务

```bash
cd services/sync
go test ./...
go vet ./...
```

## 自动发布

推送到 `main` 后，工作流会自动：

1. 运行 Flutter 分析与测试、Go 测试与 `vet`。
2. 并行构建 iOS、macOS、Android 与 Windows。
3. 发布 `ghcr.io/felixzoe/qingxu-sync` Docker 镜像。
4. 创建新版 Release、SHA-256 校验和与构建来源证明。
5. 将最终版本号回写源码，并使用 `[skip ci]` 避免重复构建。

## 文档

- [产品范围](docs/PRODUCT.md)
- [系统架构](docs/ARCHITECTURE.md)
- [同步协议 v1](docs/SYNC_PROTOCOL.md)
- [自托管部署](docs/DEPLOYMENT.md)
- [iOS 私密云端签名](docs/IOS_PRIVATE_SIGNING.md)
- [Apple 客户端开发](apps/apple/README.md)
- [Flutter 客户端开发](apps/flutter/README.md)
- [同步服务开发](services/sync/README.md)
