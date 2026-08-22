# 清序同步服务

一个面向单用户自托管场景的轻量同步服务。服务只依赖 Go 标准库，单进程运行；Docker 示例把内存上限设为 64 MiB，并把 Go 运行时软上限设为 48 MiB。

## Docker 部署（Ubuntu / 1Panel）

服务器需要已安装 Docker 和 Docker Compose。进入仓库的同步服务目录：

```bash
cd services/sync
install -m 600 .env.example .env
sudo install -d -o 65532 -g 65532 -m 700 /opt/qingxu/sync/data
```

生成同步密钥并写入 `.env`。密钥不会由服务返回，请妥善保存；iOS 和 Windows 使用同一个值：

```bash
openssl rand -hex 32
nano .env
```

把生成的 **64 个十六进制字符**完整替换到 `SYNC_TOKEN`，并设置 `SYNC_DATA_DIR=/opt/qingxu/sync/data`。服务会拒绝公开占位值、非十六进制值或长度不等于 64 的密钥；接口和健康检查都不会返回密钥。绝对数据路径位于 Git release 目录之外，自动更新或回滚 Web/代码时不会覆盖同步数据。

本项目生产地址是 `https://todo.darker.one`，示例已把它设为唯一允许的 Web 来源。确认 `.env` 中的 `SYNC_CORS_ORIGINS=https://todo.darker.one`，然后启动：

```bash
docker compose up -d --build
docker compose ps
curl http://127.0.0.1:8080/health
```

正常响应为 `{"status":"ok"}`。Compose 默认只监听服务器回环地址，不会把未加密的 8080 端口直接暴露到公网。

`todo.darker.one` 的 `/` 继续用于 Flutter Web，只把同步接口转发给 Go 服务。在 1Panel 的 OpenResty 网站配置中加入以下 location（不要把整站 `/` 改成反向代理）：

```nginx
location /v1/ {
    proxy_pass http://127.0.0.1:8080;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    client_max_body_size 2m;
    proxy_connect_timeout 5s;
    proxy_read_timeout 30s;
}

location = /health {
    proxy_pass http://127.0.0.1:8080/health;
    proxy_set_header Host $host;
}
```

网站必须启用并强制 HTTPS。验证公网入口：

```bash
curl https://todo.darker.one/health
```

iOS 和 Windows 的“服务器地址”统一填写 `https://todo.darker.one`，不要追加 `/v1/sync`；客户端会自行拼接接口路径。当前 Web 版使用浏览器本地数据，不显示原生端同步设置。

### 生产安全核对

- `SYNC_TOKEN` 必须是 `openssl rand -hex 32` 生成的 64 位 hex 值，不提交到 Git，也不要写进镜像或截图。
- 8080 端口保持 `127.0.0.1` 监听；公网只开放 OpenResty 的 HTTPS 入口。
- `data` 目录权限保持 `700` 且归容器用户 `65532:65532` 所有。
- Compose 已启用非 root 用户、只读根文件系统、删除全部 Linux capabilities、`no-new-privileges`、PID 和 64 MiB 内存限制。
- 若需要更换密钥，先在所有客户端准备新密钥，再改服务器 `.env` 并执行 `docker compose up -d`；旧密钥会立即失效。

更新服务：

```bash
git pull --ff-only
cd services/sync
docker compose up -d --build
```

确认新容器健康后，可只清理带同步服务标签的旧悬空镜像（不会删除正在运行的镜像）：

```bash
docker image prune --filter label=io.qingxu.component=sync
```

生产数据保存在 `/opt/qingxu/sync/data/store.json`（由 `SYNC_DATA_DIR` 决定），每次同步使用“临时文件 + 原子替换 + 落盘同步”写入。建议升级前做一次离线备份：

```bash
docker compose stop
sudo tar -C /opt/qingxu/sync/data -czf qingxu-sync-backup.tar.gz store.json
docker compose start
```

恢复时先执行 `docker compose stop`，解压备份到 `/opt/qingxu/sync/data/store.json`，再执行：

```bash
sudo chown -R 65532:65532 /opt/qingxu/sync/data
sudo chmod 700 /opt/qingxu/sync/data
sudo chmod 600 /opt/qingxu/sync/data/store.json
docker compose up -d
curl http://127.0.0.1:8080/health
```

备份文件包含全部任务数据（包括删除墓碑），应按敏感数据保存。

## 配置

| 环境变量 | 默认值 | 说明 |
| --- | --- | --- |
| `SYNC_TOKEN` | 无，必填 | `/v1/sync`、`/v1/ping` 的 64 位 hex Bearer Token |
| `SYNC_ADDR` | `:8080` | 容器内监听地址 |
| `SYNC_DATA_FILE` | `/data/store.json` | 持久化文件路径 |
| `SYNC_CORS_ORIGINS` | 程序默认为空；Compose 为 `https://todo.darker.one` | 允许的 Web Origin，逗号分隔；可用 `*` |
| `SYNC_MAX_BODY_BYTES` | `2097152` | 单次请求体上限 |
| `SYNC_HEALTH_URL` | `http://127.0.0.1:8080/health` | 容器健康检查地址 |

Compose 变量 `SYNC_DATA_DIR` 默认是当前目录的 `./data`；生产示例使用 `/opt/qingxu/sync/data`，确保跨 release 持久化。

## API 契约

### `GET /health`

无需鉴权，供 Docker 和反向代理探活。响应：

```json
{"status":"ok"}
```

### `POST /v1/sync`

请求头：

```http
Authorization: Bearer <SYNC_TOKEN>
Content-Type: application/json
```

请求体：

```json
{
  "deviceId": "ios-4fdb...",
  "tasks": [
    {
      "id": "task-1",
      "title": "示例任务",
      "notes": "",
      "status": "open",
      "projectId": null,
      "startAt": null,
      "deadlineAt": null,
      "completedAt": null,
      "order": 0,
      "createdAt": "2026-08-22T09:00:00Z",
      "updatedAt": "2026-08-22T10:00:00Z",
      "deletedAt": null
    }
  ]
}
```

响应包含服务端合并后的完整任务集：

```json
{
  "tasks": [],
  "serverTime": "2026-08-22T10:00:01.123Z"
}
```

合并规则：相同 `id` 比较 `updatedAt`，时间较新的文档获胜；时间相同通常保留服务端副本，但删除墓碑优先于活动副本，避免毫秒级同时间删除丢失。`deletedAt` 不得晚于 `updatedAt`。服务拒绝比当前服务器时间超前超过 5 分钟的 `updatedAt`，防止错误设备时钟把任务锁死。`deletedAt` 非空的任务不会物理删除，会继续作为墓碑返回，阻止旧设备用较早版本恢复已删除任务。服务会原样保存 TaskItem 的其他 JSON 字段，以便客户端以后扩展模型。

为控制单文件服务的内存上界，最多保存 20,000 个任务（包含墓碑），任务 JSON 总量最多 8 MiB，超限返回 HTTP 507。该服务只支持 **一个运行副本**；不要让多个容器共享同一个 `SYNC_DATA_DIR`，否则不具备跨进程合并保证。

### `GET /v1/ping`

使用与同步接口相同的 `Authorization: Bearer <SYNC_TOKEN>`。成功只返回：

```json
{"status":"ok"}
```

该接口供客户端“测试连接”使用，不读取或写入同步文件，也不会返回任务或密钥。无效密钥返回 HTTP 401。

## 本地验证

安装 Go 1.23 或更新版本后运行：

```bash
go test ./...
go vet ./...
```
