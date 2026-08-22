<p align="center">
  <img src="apps/flutter/assets/branding/qingxu-icon-master-black.png" width="112" alt="清序图标">
</p>

<h1 align="center">清序 Qingxu</h1>

清序是一款面向个人的简体中文任务管理器：本地优先、跨端一致，并允许把同步服务完整部署在自己的服务器上。

[在线使用](https://todo.darker.one) · [下载最新版本](https://github.com/FelixZoe/qingxu/releases/latest) · [构建状态](https://github.com/FelixZoe/qingxu/actions)

## 设计原则

- **本地优先**：新增、编辑、完成和删除不依赖网络；恢复联网后再合并。
- **数据可控**：同步服务器、域名、密钥和数据文件都归部署者所有。
- **一致体验**：同一套 Flutter 业务层覆盖 Web、Windows 和 iOS；iOS 底部导航使用系统原生 `UITabBar`，在 iOS 26+ 自动采用 Liquid Glass。
- **轻量运行**：生产同步服务是单个 Go 进程，Docker 内存上限为 64 MiB；Web 由 OpenResty 直接提供静态文件。
- **可维护发布**：每次推送 `main` 都会检查、测试、构建、创建 Release，并原子更新生产站点；部署失败不会替换当前 Web 版本。

## 平台与交付物

| 平台 | 交付形式 | 说明 |
| --- | --- | --- |
| Web | `https://todo.darker.one` / Web ZIP | 浏览器直接使用；当前数据保存在该浏览器本地 |
| Windows | Portable ZIP / Setup EXE | 两种文件都随 GitHub Release 发布 |
| iOS | unsigned IPA | 供个人证书或自签工具签名 |

GitHub Release 中的文件统一带版本号：

- `Qingxu-<版本>-Windows-Portable.zip`
- `Qingxu-<版本>-Windows-Setup.exe`
- `Qingxu-<版本>-Web.zip`
- `Qingxu-<版本>-iOS-unsigned.ipa`

## 自托管同步

部署时生成一个 64 个十六进制字符的随机密钥（256 bit）。在 iOS 和 Windows 的“同步设置”中填写服务器地址与同一密钥，即可接入自己的服务器：

```text
服务器地址：https://todo.darker.one
同步密钥：<openssl rand -hex 32 生成的值>
```

密钥不会由公开接口返回，也不会提交到 GitHub。客户端在 iOS 使用 Keychain、在 Windows 使用平台安全凭据存储；普通设置文件只保存服务器地址、设备名和自动同步开关。

同步采用版本化 JSON 协议，以任务 ID 和更新时间合并，并保留删除墓碑，防止离线旧设备恢复已删除任务。应用始终先写本地，网络故障不会阻塞日常使用。

> 当前服务定位为单用户、单实例自托管。HTTPS 保护传输，Bearer 密钥负责访问控制；服务端数据文件本身不是端到端加密文件，请同时做好主机权限与备份保护。

## 部署

生产环境推荐使用现有 OpenResty/1Panel 直接托管 Web 静态文件，只运行同步服务容器，以减少内存占用。仓库同时提供完整 Docker Compose 方案。

环境变量模板均已提交，真实 `.env` 被 Git 忽略：

- [`services/sync/.env.example`](services/sync/.env.example)：仅部署同步服务
- [`deploy/.env.example`](deploy/.env.example)：Docker 同时部署 Web 与同步服务

完整的 Web、Docker、HTTPS、GitHub 自动部署、备份和回滚说明见 [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md)。按照要求，仓库不重复提供 iOS/Windows 安装教程。

## 项目结构

```text
apps/flutter/       Flutter 客户端（Web / Windows / iOS）
services/sync/      Go 同步 API、持久化与容器配置
deploy/             完整 Docker 部署与 Nginx 配置
scripts/deploy/     生产服务器原子发布脚本
docs/               产品、架构、同步协议和部署文档
.github/workflows/  测试、构建、Release、镜像与生产部署
```

## 开发与验证

Flutter：

```powershell
cd apps/flutter
flutter pub get
flutter analyze
flutter test
flutter run -d chrome
```

同步服务：

```bash
cd services/sync
go test ./...
go vet ./...
```

完整 Docker 环境：

```bash
cd deploy
install -m 600 .env.example .env
# 把 SYNC_TOKEN 替换为：openssl rand -hex 32
docker compose up -d --build
curl http://127.0.0.1:8090/health
```

## 自动版本与发布

推送到 `main` 后，GitHub Actions 自动递增补丁版本，并行构建 Web、Windows、iOS 与同步服务。全部检查通过后才会：

1. 发布同步服务容器镜像到 GitHub Packages；
2. 通过受限部署账号原子更新 `todo.darker.one`；
3. 生产探活成功后创建或更新对应 GitHub Release；
4. 将最终版本号回写源码（提交带 `[skip ci]`，不会造成循环构建）。

生产部署使用独立 SSH Key 与 GitHub Actions Secrets。服务器私钥、同步密钥和真实 `.env` 永远不进入仓库。

## 文档

- [`docs/PRODUCT.md`](docs/PRODUCT.md)：产品范围与交互原则
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)：客户端、同步服务和部署架构
- [`docs/SYNC_PROTOCOL.md`](docs/SYNC_PROTOCOL.md)：同步数据结构与冲突规则
- [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md)：Web / Docker 部署、维护、备份和回滚
