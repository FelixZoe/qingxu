# 架构

## Flutter 客户端

Windows、Web 和 iOS 共用 `apps/flutter`：

- Flutter 负责界面、任务模型和离线状态。
- Web 暂存浏览器 localStorage；Windows 暂存 `%APPDATA%/Qingxu/tasks.json`，采用临时文件替换避免半写入。
- iOS 使用相同任务模型；紧凑布局顶部按平台切换为 `CupertinoNavigationBar`，保留 iOS 原生风格。
- 下一阶段把存储抽象的实现替换为 SQLite，并在其上接入增量同步队列。

## 共享边界

三端共享 Flutter UI、字段语义、同步协议和测试向量；只有平台导航、文件存储和系统能力通过适配层区分。

## 同步服务

计划采用轻量 API + SQLite：

- 每个操作具有稳定 `operationId`，服务端幂等处理。
- 客户端先写本地，再异步推送变更。
- 以服务端修订游标拉取增量，不做全量覆盖。
- 单字段最后写入优先，删除保留墓碑。
- 单用户部署不要求 Redis、PostgreSQL 或常驻 Node.js。

## 发布

GitHub Actions 分别在 Ubuntu、Windows 和 macOS Runner 构建：

- Web 静态 ZIP
- Windows Release 目录便携 ZIP
- Inno Setup 安装 EXE
- Flutter unsigned IPA

版本标签 `v*` 会自动创建 Release 并上传全部产物。
