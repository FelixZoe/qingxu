# 清序同步服务

`services/sync` 是清序的单用户自托管后台，负责合并任务、番茄钟和 RSS 阅读状态，并可选代理 RSS 摘要、翻译和任务规划请求。

返回：[项目首页](../../README.md) · [部署说明](../../docs/DEPLOYMENT.md) · [同步协议](../../docs/SYNC_PROTOCOL.md)

## 特点

- 只依赖 Go 标准库，无数据库和外部运行时依赖。
- 本地 JSON 持久化，临时文件写入、`fsync`、原子替换。
- Bearer Token 鉴权，密钥必须是 64 位十六进制值。
- 任务使用带删除墓碑的 last-write-wins 合并。
- 25 秒变更等待接口，避免高频全量轮询。
- 可选 OpenAI Chat Completions 兼容 AI 代理。
- 容器默认非 root、只读根文件系统、64 MiB 内存上限。

## 推荐运行方式

生产环境请从仓库根目录使用已发布镜像：

```bash
cd qingxu
cp .env.example .env
TOKEN=$(openssl rand -hex 32)
sed -i "s/^SYNC_TOKEN=.*/SYNC_TOKEN=$TOKEN/" .env
chmod 600 .env
sudo install -d -m 700 -o 65532 -g 65532 data
docker compose pull
docker compose up -d
curl -fsS http://127.0.0.1:8080/health
```

HTTPS、客户端连接、更新和备份步骤见 [部署说明](../../docs/DEPLOYMENT.md)。

## 本地开发

需要 Go 1.23 或更高版本。

Linux/macOS：

```bash
cd services/sync
export SYNC_TOKEN="$(openssl rand -hex 32)"
export SYNC_ADDR="127.0.0.1:8080"
export SYNC_DATA_FILE="./data/store.json"
go run ./cmd/sync-server
```

PowerShell：

```powershell
cd services/sync
$env:SYNC_TOKEN = -join ((1..32 | ForEach-Object { '{0:x2}' -f (Get-Random -Maximum 256) }))
$env:SYNC_ADDR = '127.0.0.1:8080'
$env:SYNC_DATA_FILE = './data/store.json'
go run ./cmd/sync-server
```

上述 PowerShell 随机值只适合本地开发；生产密钥请使用可信密码学随机源，例如服务器上的 `openssl rand -hex 32`。

## 配置

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `SYNC_TOKEN` | 无 | 必填；64 位十六进制密钥 |
| `SYNC_ADDR` | `:8080` | 容器/进程内部监听地址 |
| `SYNC_DATA_FILE` | `./data/store.json` | 数据文件路径 |
| `SYNC_MAX_BODY_BYTES` | `2097152` | 同步请求体上限 |
| `SYNC_CORS_ORIGINS` | 空 | 可选浏览器 Origin，多个值用逗号分隔 |
| `AI_BASE_URL` | OpenAI Chat Completions | 可选 AI 上游地址 |
| `AI_API_KEY` | 空 | 留空时 `/v1/ai` 返回未配置 |
| `AI_MODEL` | `gpt-4.1-mini` | AI 模型名称 |

仓库根 Compose 会把主机 `SYNC_LISTEN` 映射到容器 8080，并将 `SYNC_DATA_DIR` 挂载为容器 `/data`；不要混淆主机变量与进程内部的 `SYNC_ADDR`、`SYNC_DATA_FILE`。

## HTTP 接口

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| `GET` | `/health` | 无鉴权健康检查，同时验证数据目录可写 |
| `GET` | `/v1/ping` | 验证 Bearer Token |
| `POST` | `/v1/sync` | 双向合并完整同步状态 |
| `GET` | `/v1/changes?since=<revision>` | 最长等待 25 秒的修订号通知 |
| `POST` | `/v1/ai` | 可选 AI 摘要、翻译与任务规划 |

请求和合并规则见 [同步协议 v1](../../docs/SYNC_PROTOCOL.md)。

## 测试

```bash
cd services/sync
go test ./...
go vet ./...
go build ./cmd/sync-server
```

提交到 `main` 后，GitHub Actions 会重复执行测试与 `vet`、构建容器，并发布 `ghcr.io/felixzoe/qingxu-sync`。

## 存储边界

- 单次最多 10,000 个任务。
- 服务端最多保存 20,000 个任务（包含墓碑）。
- 任务 JSON 总量最多 8 MiB，磁盘状态文件最多 10 MiB。
- 单实例写入；多个进程不能共享同一个数据文件。
- RSS 正文和 AI 密钥都不会写入同步状态。
