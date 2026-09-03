# 清序同步协议 v1

本文描述当前服务端已经实现并由自动化测试覆盖的 HTTP/JSON 协议。示例基址为 `https://todo.darker.one`；自托管时替换为自己的 HTTPS 域名。

返回：[项目首页](../README.md) · [系统架构](ARCHITECTURE.md) · [部署说明](DEPLOYMENT.md)

## 约定

- 生产环境只使用 HTTPS。
- `/v1/*` 使用 `Authorization: Bearer <SYNC_TOKEN>`。
- `SYNC_TOKEN` 必须是 64 个十六进制字符，即 256-bit 随机值。
- JSON 编码为 UTF-8；接口响应包含 `Cache-Control: no-store`。
- 时间使用 UTC RFC 3339，客户端应优先生成带毫秒或更高精度的值。
- 未说明的字段应被旧客户端忽略，以便协议向后兼容。

## 接口一览

| 方法 | 路径 | 鉴权 | 用途 |
| --- | --- | --- | --- |
| `GET` | `/health` | 否 | 检查进程与数据目录可写性 |
| `GET` | `/v1/ping` | 是 | 测试地址和密钥，不读写数据 |
| `POST` | `/v1/sync` | 是 | 合并并返回任务、番茄钟和 RSS 状态 |
| `GET` | `/v1/changes?since=<revision>` | 是 | 等待修订号变化，最长 25 秒 |
| `POST` | `/v1/ai` | 是 | 可选 RSS 摘要、翻译和任务规划代理 |

## 健康检查

```http
GET /health
```

成功：

```json
{"status":"ok"}
```

健康检查不仅确认 HTTP 进程存在，还确认数据目录可写。存储不可用时返回 `503` 和 `{"status":"unavailable"}`。

## 验证连接

```http
GET /v1/ping
Authorization: Bearer <SYNC_TOKEN>
```

成功只返回：

```json
{"status":"ok"}
```

该接口不会读取、修改或返回用户数据，客户端“测试连接”使用它验证配置。

## 双向同步

```http
POST /v1/sync
Authorization: Bearer <SYNC_TOKEN>
Content-Type: application/json
```

请求示例：

```json
{
  "deviceId": "iphone",
  "tasks": [
    {
      "id": "task-1",
      "title": "提交周报",
      "notes": "",
      "status": "open",
      "projectId": null,
      "startAt": "2026-08-28T09:00:00.000Z",
      "deadlineAt": null,
      "completedAt": null,
      "order": 0,
      "createdAt": "2026-08-28T08:00:00.000Z",
      "updatedAt": "2026-08-28T08:30:00.000Z",
      "deletedAt": null
    }
  ],
  "pomodoro": {
    "mode": "focus",
    "status": "running",
    "remainingSeconds": 1500,
    "completedFocusSessions": 2,
    "focusMinutes": 25,
    "shortBreakMinutes": 5,
    "longBreakMinutes": 15,
    "endsAt": "2026-08-28T08:55:00.000Z",
    "updatedAt": "2026-08-28T08:30:00.000Z"
  },
  "rss": {
    "subscriptions": [],
    "folders": [],
    "articleStates": [],
    "updatedAt": "2026-08-28T08:30:00.000Z"
  }
}
```

响应返回服务端合并后的完整状态：

```json
{
  "tasks": [],
  "pomodoro": {
    "mode": "focus",
    "status": "running",
    "remainingSeconds": 1500,
    "completedFocusSessions": 2,
    "focusMinutes": 25,
    "shortBreakMinutes": 5,
    "longBreakMinutes": 15,
    "endsAt": "2026-08-28T08:55:00.000Z",
    "updatedAt": "2026-08-28T08:30:00.000Z"
  },
  "rss": {
    "subscriptions": [],
    "folders": [],
    "articleStates": [],
    "updatedAt": "2026-08-28T08:30:00.000Z"
  },
  "serverTime": "2026-08-28T08:30:01.123Z",
  "revision": 1787905801123
}
```

`deviceId` 长度为 1–128 个字符，只用于日志识别。服务端解释任务的 `id`、`updatedAt` 与 `deletedAt`，其余字段作为完整 JSON 保存，因此客户端可以在不迁移服务端代码的情况下增加普通任务字段。

客户端可以省略尚未支持的 `pomodoro` 或 `rss`。服务端会保留已有文档，不会因旧客户端缺少字段而清空数据。

## 合并规则

### 任务

1. `id` 是任务的永久身份。
2. 相同 `id` 比较 UTC `updatedAt`，较新的完整任务获胜。
3. 时间相同时保留服务端副本；若活动副本与删除墓碑冲突，墓碑获胜。
4. `deletedAt` 非空表示软删除，并且不得晚于 `updatedAt`。
5. 墓碑继续保存并返回，防止离线旧设备恢复已删除任务。
6. 比服务器当前时间超前超过 5 分钟的 `updatedAt` 会被拒绝。
7. 重复提交相同快照是幂等操作。

### 番茄钟

番茄钟是单例 LWW 文档，同样比较 `updatedAt`。运行状态使用绝对 UTC `endsAt`；暂停或空闲时以 `remainingSeconds` 为权威值。

- `phaseID`：每次开始、恢复或自动进入下一阶段时更新，防止系统实时活动复用上一阶段的倒计时视图。
- `dailyFocusGoal`：1–24 的每日番茄目标，由 iOS、安卓和桌面端共享。
- `focusHistory`：已完成或主动结束的专注记录；客户端据此计算当天进度与 GitHub 风格年度热力图。

新增字段保持向后兼容：旧客户端未发送这些字段时，服务端保留现有番茄文档；新客户端读取旧文档时使用默认目标 4，并生成本地阶段标识。

`focusMinutes`、`shortBreakMinutes` 和 `longBreakMinutes` 保存自定义阶段时长。客户端用响应中的 `serverTime` 计算本地时钟偏移，使不同设备显示同一个剩余时间。

### RSS

RSS 是单例 LWW 文档，保存：

- 订阅地址和来源信息。
- 来源分类。
- 每篇文章的稳定 ID、已读、收藏和阅读进度。

文章标题、摘要、HTML 和正文不上传同步服务。每台设备自行抓取来源内容，再按稳定文章 ID 应用同步状态。

## 实时变更通知

```http
GET /v1/changes?since=1787905801123
Authorization: Bearer <SYNC_TOKEN>
```

数据变化时立即返回：

```json
{"revision":1787905801124,"changed":true}
```

25 秒内没有变化时返回当前修订号与 `changed: false`。该接口不携带用户数据，客户端只有在 `changed` 为真且修订号更新时才调用 `/v1/sync`。

前台设备只保持一个休眠请求；5 分钟完整同步用于网络切换和断线恢复。客户端持久化最近修订号，并在失败时使用 1、2、4、8、16 秒封顶的带抖动退避。反向代理的读取超时应大于 25 秒，并且不得缓存此接口。

`revision` 是实例内的单调修订标识，不是业务时间戳，也不能跨服务端数据目录比较。恢复备份或更换服务器后，客户端通过下一次完整同步重新建立基线。

## AI 代理

只有服务器配置了 `AI_API_KEY` 时该接口可用：

```http
POST /v1/ai
Authorization: Bearer <SYNC_TOKEN>
Content-Type: application/json
```

### RSS 摘要

```json
{
  "mode": "rss_summary",
  "title": "文章标题",
  "content": "文章正文",
  "prompt": "可选的自定义摘要要求"
}
```

`prompt` 为空时使用内置默认要求：一句话结论、3 个关键点和一个可执行行动，总计不超过 260 个汉字。

### RSS 翻译

```json
{
  "mode": "rss_translation",
  "content": "[\"First paragraph\",\"Second paragraph\"]"
}
```

`content` 是一个 JSON 字符串数组的序列化文本，最多 40 段。响应保持段落数量与顺序，供客户端覆盖原文节点而不是打开第二个翻译页面。

### 任务规划

```json
{
  "mode": "task_plan",
  "goal": "今天完成报告并留出复习时间",
  "tasks": [
    {"title": "写报告", "scheduledAt": "2026-08-28T09:00:00Z"}
  ]
}
```

最多提交 200 个任务。模型被要求返回不超过 6 个、未来 0–14 天内的简洁建议。

AI 成功响应统一为：

```json
{"text":"模型返回文本"}
```

未配置 AI 返回 `503 ai_not_configured`；上游模型不可用返回 `502 ai_request_failed`。AI 请求正文上限为 80 KiB，不影响普通同步接口。

## 限制

| 项目 | 默认限制 |
| --- | --- |
| 同步请求体 | 2 MiB，可用 `SYNC_MAX_BODY_BYTES` 调整 |
| 单次任务数 | 10,000 |
| 服务端任务总数 | 20,000，包含墓碑 |
| 任务 JSON 总量 | 8 MiB |
| 磁盘状态文件 | 10 MiB |
| `deviceId` | 1–128 个字符 |
| 未来时钟偏差 | 最多 5 分钟 |
| 变更等待 | 最长 25 秒 |

当前服务只支持单实例写入；多个进程不得共享同一个 `store.json`。

## 错误格式

```json
{
  "error": {
    "code": "invalid_task",
    "message": "..."
  }
}
```

| HTTP 状态 | 常见原因 |
| --- | --- |
| `400` | 非法 JSON、时间、任务、修订号或 AI 参数 |
| `401` | Bearer 密钥缺失或错误 |
| `403` | 浏览器 Origin 不在允许列表 |
| `405` | HTTP 方法不受支持 |
| `413` | 请求体超过限制 |
| `500` | 存储写入失败 |
| `502` | AI 上游失败 |
| `503` | 数据目录不可用或 AI 未配置 |
| `507` | 服务端任务数量或数据容量超限 |

## 协议演进

磁盘格式具有显式版本号。v1 客户端必须忽略不认识的普通任务字段；服务端保留完整任务 JSON。未来若引入增量 operation log、端到端加密或多用户认证，将使用明确的新版本或迁移流程，不会静默改变本文的 v1 语义。
