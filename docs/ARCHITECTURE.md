# 清序架构

## 客户端

四个平台共用 `apps/flutter` 的任务模型、状态控制器、同步客户端与 UI 组件。

- iOS：Flutter 业务界面嵌入原生 `UITabBarController`；WidgetKit 扩展提供桌面小组件和 ActivityKit 实时活动。
- Android：Flutter Material 底部导航。
- Windows / macOS：适合桌面的侧边导航与自适应内容区。
- 本机持久化使用应用支持目录；同步密钥由 `flutter_secure_storage` 写入平台安全存储。

主题设置属于设备偏好，不参与同步。任务、项目字段、备注、日期、完成/删除状态及番茄钟状态属于用户数据，会自动同步。

## 状态与同步

`TaskController` 是当前应用级状态入口：

1. 启动后先显示首帧，再并行加载本地任务、番茄钟与同步设置。
2. 编辑立即写本地原子文件，并在约 1.2 秒防抖后同步。
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
2. 并行构建 iOS、Android、Windows、macOS。
3. 发布 `ghcr.io/felixzoe/qingxu-sync`。
4. 生成 Release、SHA-256 校验和和 GitHub artifact attestation。
5. 将最终版本号回写源码，提交带 `[skip ci]`，避免循环构建。

产品预览站独立维护与部署，不进入本仓库，也不由该工作流覆盖。
