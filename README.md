<p align="center">
  <img src="apps/flutter/assets/branding/qingxu-icon-master-black.png" width="112" alt="清序图标">
</p>

<h1 align="center">清序 Qingxu</h1>

<p align="center">简体中文、本地优先、可自托管同步的跨平台任务与专注应用。</p>

<p align="center">
  <a href="https://todo.darker.one">产品预览</a> ·
  <a href="https://github.com/FelixZoe/qingxu/releases/latest">下载最新版</a> ·
  <a href="https://github.com/FelixZoe/qingxu/actions">构建状态</a>
</p>

## 已有能力

- 收集箱、今天、项目、备注、截止时间与完成状态，断网时照常编辑。
- 番茄钟支持自定义专注、短休息和长休息时长，并在 iOS、Android、Windows、macOS 间自动同步；运行中使用服务端时间校准剩余时间。
- 前台客户端使用低占用的长连接变更通知；一端开始、暂停或重置番茄钟后，其他在线设备会立即拉取同一个结束时刻，不再每 3 秒上传完整数据。
- iOS 与 macOS 使用完整 SwiftUI 原生客户端；iOS 支持系统底部导航、锁屏实时活动、灵动岛、今日任务与专注状态小组件。
- Android 与 Windows 使用 Flutter 客户端，四端共用同一份同步数据与协议。
- 米白蓝日间主题与黑绿夜间主题，跟随系统或手动切换。
- 单用户自托管同步服务；真实密钥只保存在服务端 `.env` 与客户端系统安全存储。
- `main` 每次更新自动分析、测试并构建四个平台，同时发布 Docker 镜像、Release、SHA-256 校验和与构建来源证明。

## 下载

| 平台 | Release 文件 | 状态 |
| --- | --- | --- |
| iOS | `Qingxu-<版本>-iOS-unsigned.ipa` | SwiftUI 原生；自签安装；包含灵动岛与小组件 |
| Android | `Qingxu-<版本>-Android.apk` | 直接安装 APK |
| Windows | `Windows-Portable.zip` / `Windows-Setup.exe` | 便携版与安装版 |
| macOS | `macOS-Portable.zip` / `macOS.dmg` | SwiftUI 原生；当前为未公证构建 |

请只从[本仓库 Releases](https://github.com/FelixZoe/qingxu/releases/latest)下载，并用同一 Release 的 `SHA256SUMS.txt` 校验文件。未配置商业证书时，Windows SmartScreen 或 macOS Gatekeeper 可能提示未知发布者；工作流已预留 Windows 可信 PFX 签名变量。

## 更新方式

四端共用 GitHub Release 版本来源，但受系统安全模型限制，更新能力不同：Windows 可下载后替换并重启，Android 可下载 APK 后交给系统确认安装，macOS 正式自动更新需要 Developer ID 签名与公证，iOS 自签版只能提示并下载新版 IPA，再由签名工具重新安装。原生 Swift iOS/macOS 不能使用 Flutter 热补丁，iOS 也不允许应用静默替换自身可执行文件。

## 3 分钟部署自己的同步服务

服务器需要 Docker Compose v2 和一个已启用 HTTPS 的域名。

```bash
git clone https://github.com/FelixZoe/qingxu.git
cd qingxu
cp .env.example .env
TOKEN=$(openssl rand -hex 32)
sed -i "s/^SYNC_TOKEN=.*/SYNC_TOKEN=$TOKEN/" .env
chmod 600 .env
sudo install -d -m 700 -o 65532 -g 65532 data
docker compose pull
docker compose up -d
curl http://127.0.0.1:8080/health
echo "$TOKEN"
```

在 Nginx、Caddy 或 1Panel 中把域名的 `/v1/` 和 `/health` 反向代理到 `http://127.0.0.1:8080`。然后在每台清序客户端的“设置 → 多端同步”填写：

```text
服务器地址：https://你的域名
同步密钥：上一步生成的 64 位十六进制 TOKEN
自动同步：开启
```

客户端会自动同步全部用户数据；不需要手动创建账号，也不要在服务器地址后追加 `/v1/sync`。完整的反向代理、更新、备份与恢复步骤见[部署文档](docs/DEPLOYMENT.md)。

## 数据与同步

- 任务先原子写入本机，再异步同步；服务器不可用不会阻塞日常操作。
- 同一任务按 `updatedAt` 合并，删除墓碑优先，避免旧设备复活已删除任务。
- 番茄钟以共享的 `endsAt` 和服务端时间计算剩余秒数；开始、暂停、重置、跳过和阶段完成都会在约 250ms 后推送，并通过 `/v1/changes` 立即通知其他前台设备。无变化时请求在服务端休眠，不执行高频完整同步；5 分钟完整同步只用于容错兜底。
- 服务端数据保存在 Docker 卷 `/data/store.json`。同步不是备份，请定期备份该文件。
- 当前服务面向一个人使用；一套部署对应一个 256-bit 随机同步密钥。

## 项目结构

```text
apps/apple/         SwiftUI iOS / macOS 客户端与 XcodeGen 工程定义
apps/flutter/       Flutter Android / Windows 客户端
services/sync/      Go 同步服务与容器镜像
scripts/ios/        可重复生成 iOS 小组件扩展目标的构建脚本
scripts/windows/    Windows 安装包配置
docs/               产品、架构、协议与自托管文档
.github/workflows/  四端构建、Docker 与自动 Release
```

`todo.darker.one` 是介绍与下载预览站，不是 Web 客户端；站点源码与产品仓库分离，不会随本仓库发布。

## 开发

```bash
cd apps/flutter
flutter pub get
flutter analyze
flutter test
flutter run -d windows   # 或 android
```

Apple 原生端需要 macOS、Xcode 与 XcodeGen：

```bash
cd apps/apple
xcodegen generate
open QingxuApple.xcodeproj
```

同步服务：

```bash
cd services/sync
go test ./...
go vet ./...
```

更多资料：[产品范围](docs/PRODUCT.md) · [架构](docs/ARCHITECTURE.md) · [同步协议](docs/SYNC_PROTOCOL.md) · [部署](docs/DEPLOYMENT.md)
