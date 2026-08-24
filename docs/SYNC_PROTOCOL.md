# 清序同步协议 v1

本文描述当前已经实现并由自动化测试覆盖的协议。服务器基址示例为 `https://todo.darker.one`。

## 认证与传输

- 生产环境只允许 HTTPS。
- `/v1/*` 使用 `Authorization: Bearer <SYNC_TOKEN>`。
- `SYNC_TOKEN` 必须是 64 个十六进制字符（256-bit 随机值）。
- 密钥错误返回 `401`；公开接口永远不会返回密钥。
- JSON 使用 UTF-8，响应带 `Cache-Control: no-store`。

## 健康检查

`GET /health` 无需鉴权，供 Docker、OpenResty 和监控使用：

```json
{"status":"ok"}
```

该响应同时说明进程可用且数据目录仍可写。

## 验证连接

`GET /v1/ping` 需要 Bearer 密钥。成功只返回：

```json
{"status":"ok"}
```

它不读取、不修改也不返回任何任务，客户端“测试连接”使用该接口。

## 同步

`POST /v1/sync`

请求：

```json
{
  "deviceId": "my-windows-pc",
  "tasks": [
    {
      "id": "task-1",
      "title": "提交周报",
      "notes": "",
      "status": "open",
      "projectId": null,
      "startAt": null,
      "deadlineAt": null,
      "completedAt": null,
      "order": 0,
      "createdAt": "2026-08-22T09:00:00.000Z",
      "updatedAt": "2026-08-22T10:00:00.000Z",
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
    "endsAt": "2026-08-22T10:25:00.000Z",
    "updatedAt": "2026-08-22T10:00:00.000Z"
  },
  "rss": {
    "subscriptions": [],
    "folders": [],
    "articleStates": [],
    "updatedAt": "2026-08-22T10:00:00.000Z"
  }
}
```

响应返回服务器合并后的完整任务集合、番茄钟单例状态、RSS 阅读状态与服务端时间：

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
    "endsAt": "2026-08-22T10:25:00.000Z",
    "updatedAt": "2026-08-22T10:00:00.000Z"
  },
  "rss": {
    "subscriptions": [],
    "folders": [],
    "articleStates": [],
    "updatedAt": "2026-08-22T10:00:00.000Z"
  },
  "serverTime": "2026-08-22T10:00:01.123Z",
  "revision": 1787460000123
}
```

`deviceId` 长度为 1–128 个字符。服务端解释 `id`、`updatedAt` 和 `deletedAt`，其他任务字段原样保存，以便向后兼容新增字段。

## 合并规则

1. `id` 是任务的永久身份。
2. 同一 `id` 的文档比较 UTC `updatedAt`，较新的完整文档获胜。
3. `updatedAt` 相同时，服务端现有文档保持稳定；但活动副本与删除墓碑冲突时墓碑获胜。
4. `deletedAt` 非空表示软删除，并且不得晚于 `updatedAt`。
5. 墓碑继续保存和返回，防止旧设备恢复已删除任务。
6. 比服务器当前时间超前超过 5 分钟的 `updatedAt` 会被拒绝，避免错误设备时钟长期锁死任务。
7. 重复提交相同快照是幂等的。

番茄钟是单例 LWW 文档，同样比较 `updatedAt`。运行状态用绝对 UTC `endsAt` 表示；`remainingSeconds` 是暂停或空闲时的权威值。`focusMinutes`、`shortBreakMinutes` 与 `longBreakMinutes` 保存三段自定义时长，旧客户端缺少这些字段时按 25/5/15 分钟处理。客户端根据响应中的 `serverTime` 估算时钟偏移，因此各端不会依赖各自设备时钟单独递减。

RSS 也是单例 LWW 文档，保存订阅、来源分类以及每篇文章的已读、收藏和阅读进度状态。文章标题、摘要和正文不上传同步服务；不同设备会自行从各 RSS 来源抓取文章，再按稳定文章 ID 套用同步状态。旧客户端不发送 `rss` 时，服务端保留已有 RSS 状态。

## 实时变更通知

`GET /v1/changes?since=<revision>` 需要 Bearer 密钥。服务端在修订号未变化时最长等待 25 秒；数据变化会立即唤醒请求：

```json
{"revision":1787460000124,"changed":true}
```

等待超时但没有变化时返回当前修订号与 `changed: false`。该接口不返回任务或番茄钟正文，客户端只有在 `changed` 为真且修订号更新时才调用 `/v1/sync`。因此一个前台设备只保持一个休眠请求，不进行 3 秒一次的完整 JSON 轮询；客户端另有 5 分钟低频完整同步作为断线兜底。

这是文档级 LWW，不是逐字段合并。两个设备同时编辑同一任务时，时间较新的完整任务覆盖较旧任务；客户端应使用系统 UTC 时间并保持自动校时。

## 限制与错误

- 请求体默认上限：2 MiB；超出返回 `413`。
- 单次最多 10,000 个任务。
- 服务端最多保存 20,000 个任务（含墓碑），任务 JSON 总量最多 8 MiB；超出返回 `507`。
- 非法任务、时间或 JSON 返回 `400`。
- 不支持的方法返回 `405`。
- 存储失败返回 `500`。
- 服务只支持单实例写入；多个进程不得共享同一数据文件。

错误响应：

```json
{
  "error": {
    "code": "invalid_task",
    "message": "..."
  }
}
```

## 协议演进

磁盘格式已有显式版本号。v1 客户端必须忽略它不认识的任务字段；服务端保留完整任务 JSON。未来如果引入增量 operation log、端到端加密或多用户认证，将使用明确的新端点/版本迁移，而不会悄悄改变本文件中的 v1 语义。
