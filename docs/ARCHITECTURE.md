# 清序架构

## 客户端

Windows、Web 和 iOS 共用 `apps/flutter` 中的任务模型、状态控制器与界面组件。

- 所有任务操作先写本地，不等待网络响应。
- Windows 数据保存到 `%APPDATA%/Qingxu/tasks.json`；iOS 保存到 App Documents；Web 使用浏览器持久化适配层。
- Windows 与 iOS 可配置自托管同步。服务器地址和设备名进入普通设置文件，同步密钥进入 iOS Keychain / Windows 平台安全凭据存储。
- 客户端启动时同步；开启自动同步后，本地变化经 1.2 秒防抖上传。并发请求会排队，失败不修改本地任务。
- iOS 底部使用系统 `UITabBarController`；使用 iOS 26 SDK 构建时由系统呈现 Liquid Glass，旧系统保留原生兼容样式。
- Web 当前用于浏览器本地任务管理，不显示原生安全存储依赖的同步设置。

## 同步服务

`services/sync` 是只依赖 Go 标准库的单进程服务：

- `GET /health`：公开探活，同时验证数据目录可写；
- `GET /v1/ping`：验证 Bearer 密钥，不读取任务；
- `POST /v1/sync`：接收本地完整任务快照，返回合并后的完整快照；
- 相同 ID 按 `updatedAt` 最后写入优先；同时间删除墓碑优先；
- 数据以版本化 JSON 保存，采用临时文件、文件 `fsync`、原子替换和目录 `fsync`；
- 64-hex（256-bit）密钥使用常量时间摘要比较；
- 单次请求 2 MiB、总计 20,000 个任务 / 8 MiB，防止单文件服务失控；
- 只支持一个运行副本，不允许多个容器共享同一数据目录。

当前范围是单用户自托管，因此不引入 PostgreSQL、Redis、消息队列或常驻 Node.js。若未来需要大规模增量同步，会作为新协议版本迁移，不能把尚未实现的 operation log 写成当前契约。

## 数据流

```text
本地操作 → 本地原子保存 → 防抖同步 → HTTPS /v1/sync
                                      ↓
                                Go 合并与落盘
                                      ↓
合并后本地保存 ← 完整合并快照 ← 同一响应
```

任务删除使用墓碑而非物理删除。这样离线设备重新上线时，较旧的活动副本不会恢复已经删除的任务。

## 生产部署

`todo.darker.one` 使用现有 1Panel OpenResty：

- Flutter Web 是不可变静态 release 目录，`current` 相对软链接原子切换；
- `/v1/` 与 `/health` 反向代理到 `127.0.0.1:8080`；
- 同步容器以非 root、只读根文件系统、64 MiB 内存上限运行；
- 同步数据和 `.env` 位于 release 目录之外；
- 服务器只允许专用部署用户调用 root 持有的固定 helper；helper 从精确 Git commit 获取同步源码，不执行部署用户上传的脚本或 Dockerfile；
- Web 和同步服务均保留最近三个版本，激活失败时恢复上一容器和软链接。

完整 Docker 方案位于 `deploy/`，生产与备份说明见 `docs/DEPLOYMENT.md`。

## 发布顺序

GitHub Actions 的门禁顺序为：

1. Flutter 分析与测试、Web / Windows / iOS 构建；
2. Go 测试、vet、Windows 交叉编译与 Docker 构建；
3. 发布同步镜像到 GitHub Packages；
4. 原子部署生产站点并精确校验 `version.json`；
5. 创建 GitHub Release；
6. 远端 `main` 仍等于本次已测试 commit 时，回写版本号。
