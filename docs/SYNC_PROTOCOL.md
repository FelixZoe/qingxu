# 同步协议草案 v1

## 基本概念

- `entityId`：实体永久 ID，UUID v4。
- `operationId`：一次本地变更的永久 ID，用于幂等。
- `clientId`：设备安装实例 ID。
- `revision`：服务端单调递增游标。
- `updatedAt`：客户端 UTC 时间，仅用于字段冲突判断，不作为拉取游标。
- `deletedAt`：软删除时间；非空实体不会再出现在普通列表。

## 推送

`POST /v1/sync/push`

```json
{
  "clientId": "uuid",
  "operations": [
    {
      "operationId": "uuid",
      "entityType": "task",
      "entityId": "uuid",
      "baseRevision": 42,
      "changedFields": ["title", "updatedAt"],
      "payload": {
        "title": "提交周报",
        "updatedAt": "2026-08-22T10:00:00.000Z"
      }
    }
  ]
}
```

服务端对同一 `operationId` 重复请求返回同一结果。

## 拉取

`GET /v1/sync/pull?cursor=42&limit=500`

```json
{
  "cursor": 57,
  "hasMore": false,
  "changes": []
}
```

## 冲突策略

1. 不同字段的并发修改直接合并。
2. 同一字段按 `updatedAt`、`clientId` 确定稳定胜者。
3. 完成状态不会覆盖较新的重新打开操作。
4. 删除是普通字段变更，可被更晚的明确恢复操作撤销。
5. 清单项拥有独立 ID，不以数组位置作为身份。

## 兼容性

请求携带 `X-Qingxu-Protocol: 1`。服务端至少保留最近两个协议版本的读取兼容；破坏性字段变更必须通过新增字段迁移。

