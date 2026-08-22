# 清序架构

## 客户端

四个平台共用同一份 JSON 同步协议与 Go 服务端，但客户端按平台分为两套实现。

- iOS：`apps/apple` 的纯 SwiftUI 应用，使用系统 `TabView`、`NavigationStack`、WidgetKit 与 ActivityKit；不嵌入 Flutter 引擎。
- macOS：`apps/apple` 的纯 SwiftUI 应用，使用 `NavigationSplitView` 和原生 Settings 场景。
- Android：`apps/flutter` 的 Flutter 客户端与 Material 底部导航。
- Windows：`apps/flutter` 的 Flutter 桌面客户端、侧边导航、便携包和安装包。
- 本机持久化使用平台应用数据目录；同步密钥分别由 Apple Keychain 和 `flutter_secure_storage` 写入平台安全存储。

主题设置属于设备偏好，不参与同步。任务、项目字段、备注、日期、完成/删除状态及番茄钟状态属于用户数据，会自动同步。

## 状态与同步

Flutter 端由 `TaskController` 管理状态，Apple 原生端由 `AppStore` 管理状态；二者遵循相同流程：

1. 启动后优先载入本地任务、番茄钟与同步设置。
2. 编辑立即写本地原子文件，并在短暂防抖后同步。
3. 普通状态每 30 秒拉取；运行中的番茄钟每 3 秒拉取。
4. 任务按 ID 和更新时间合并，删除墓碑优先。
5. 番茄钟是单例 LWW 文档；运行状态保存绝对 `endsAt`，客户端使用 `serverTime` 校准后的时钟计算剩余值。

iOS 每次用户数据变化时还会把一个最小快照写入 App Group，供 WidgetKit 读取；运行中的番茄钟同时更新 ActivityKit。实时活动本身不发网络请求。

## 同步服务

`services/sync` 是只依赖 Go 标准库的单进程 HTTP 服务：

- `GET /health`：容器与反向代理探活。
- `GET /v1/ping`：验证 Bearer 密钥。
- `POST /v1/sync`：合并并返回完整任务集、番茄钟状态和服务端时间。
- 数据以临时文件、`fsync`、原子替换的顺序写入 `/data/store.json`。

部署定位是单用户、单实例。Docker 默认非 root、只读根文件系统、64 MiB 内存上限；公网入口由现有 Nginx/OpenResty/Caddy 提供 HTTPS。

## 发布

GitHub Actions 在每次 `main` 更新时：

1. 运行 Flutter 分析与测试、Go 测试与 vet。
2. 并行用 Xcode 构建原生 iOS/macOS，并用 Flutter 构建 Android/Windows。
3. 发布 `ghcr.io/felixzoe/qingxu-sync`。
4. 生成 Release、SHA-256 校验和和 GitHub artifact attestation。
5. 将最终版本号回写源码，提交带 `[skip ci]`，避免循环构建。

产品预览站独立维护与部署，不进入本仓库，也不由该工作流覆盖。
