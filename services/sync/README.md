# 清序同步服务

面向单用户自托管场景的轻量 Go 同步服务，保存任务、删除墓碑与番茄钟状态。只依赖 Go 标准库；Docker 默认非 root、只读根文件系统、64 MiB 内存上限与 48 MiB Go 软限制。

推荐直接使用仓库根目录的预构建镜像方案：

```bash
cd qingxu
cp .env.example .env
TOKEN=$(openssl rand -hex 32)
sed -i "s/^SYNC_TOKEN=.*/SYNC_TOKEN=$TOKEN/" .env
chmod 600 .env
docker compose up -d
curl http://127.0.0.1:8080/health
```

需要从源码构建时：

```bash
cd services/sync
cp .env.example .env
# 把 SYNC_TOKEN 换为 openssl rand -hex 32 的输出
docker compose up -d --build
```

接口：

- `GET /health`：无鉴权健康检查。
- `GET /v1/ping`：验证 `Authorization: Bearer <SYNC_TOKEN>`。
- `POST /v1/sync`：双向合并任务与番茄钟状态，返回服务端时间。
- `GET /v1/changes?since=<revision>`：最长等待 25 秒的变更通知；仅修订号变化时客户端再拉完整数据。
- `POST /v1/ai`：可选的 RSS 摘要和任务规划代理；复用同步密钥鉴权，模型密钥不会下发到客户端。

如需启用 AI，在 `.env` 填写 `AI_API_KEY`。默认调用 OpenAI Chat Completions；使用其他兼容服务时一并修改 `AI_BASE_URL` 和 `AI_MODEL`。未配置时同步功能保持正常，客户端的 AI 入口会明确提示尚未启用。

完整的 HTTPS 反向代理、客户端填写、更新、备份和恢复步骤见 [`docs/DEPLOYMENT.md`](../../docs/DEPLOYMENT.md)，协议细节见 [`docs/SYNC_PROTOCOL.md`](../../docs/SYNC_PROTOCOL.md)。

本地验证：

```bash
go test ./...
go vet ./...
```
