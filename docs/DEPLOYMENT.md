# 清序同步服务部署

本文用于在自己的 Linux 服务器上部署清序同步与可选 AI 代理。客户端安装包从 [GitHub Releases](https://github.com/FelixZoe/qingxu/releases/latest) 获取；`todo.darker.one` 是独立预览站，不是部署后台所必需。

返回：[项目首页](../README.md) · [系统架构](ARCHITECTURE.md) · [同步协议](SYNC_PROTOCOL.md)

## 部署结果

完成后你会得到：

- 一个只监听服务器本机 `127.0.0.1:8080` 的 Go 服务。
- 一个由 Nginx、Caddy 或 1Panel 提供 HTTPS 的公开地址。
- 一个 64 位十六进制同步密钥，填写到自己的所有客户端。
- 一个需要单独备份的 `data/store.json` 数据文件。

## 准备

- Linux 服务器，推荐至少 1 核 CPU、512 MiB 内存。
- Docker Engine 与 Docker Compose v2。
- 已解析到服务器的域名和有效 HTTPS 证书。
- Nginx、Caddy 或 1Panel OpenResty 反向代理。

确认环境：

```bash
docker version
docker compose version
openssl version
```

## 一键启动

```bash
git clone https://github.com/FelixZoe/qingxu.git
cd qingxu
cp .env.example .env

TOKEN=$(openssl rand -hex 32)
sed -i "s/^SYNC_TOKEN=.*/SYNC_TOKEN=$TOKEN/" .env
chmod 600 .env

sudo install -d -m 700 -o 65532 -g 65532 data
docker compose pull
docker compose config --quiet
docker compose up -d
docker compose ps
curl -fsS http://127.0.0.1:8080/health
echo "$TOKEN"
```

预期健康响应：

```json
{"status":"ok"}
```

请立即把 `$TOKEN` 保存到密码管理器。服务端不会通过接口返回该密钥，遗失后只能更换密钥并重新配置所有设备。

## 环境变量

仓库根目录 `.env` 由 `compose.yaml` 读取。

| 变量 | 默认值 | 用途 |
| --- | --- | --- |
| `SYNC_TOKEN` | 无 | 必填；`openssl rand -hex 32` 生成的 64 位十六进制密钥 |
| `SYNC_LISTEN` | `127.0.0.1:8080` | 主机监听地址；建议只绑定回环地址 |
| `SYNC_DATA_DIR` | `./data` | 主机数据目录，可改为绝对路径 |
| `SYNC_MAX_BODY_BYTES` | `2097152` | 单次同步请求体上限，默认 2 MiB |
| `GOMEMLIMIT` | `48MiB` | Go 运行时软内存限制 |
| `AI_BASE_URL` | OpenAI Chat Completions | 可选 AI 兼容接口地址 |
| `AI_API_KEY` | 空 | 留空即禁用服务端 AI 代理 |
| `AI_MODEL` | `gpt-4.1-mini` | 服务端 AI 模型名称 |

启用自托管 AI 代理时只需编辑 `.env`：

```dotenv
AI_BASE_URL=https://api.openai.com/v1/chat/completions
AI_API_KEY=你的密钥
AI_MODEL=gpt-4.1-mini
```

然后执行 `docker compose up -d`。AI 密钥只进入服务器容器环境，不会随同步响应下发给客户端。

## 配置 HTTPS 反向代理

服务默认只监听 `127.0.0.1:8080`。不要直接把未加密的 8080 端口开放到公网。

### Nginx / 1Panel OpenResty

将以下规则加入目标网站配置。根路径可以继续展示你自己的网页，只转发同步接口和健康检查：

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
    proxy_read_timeout 40s;
}

location = /health {
    proxy_pass http://127.0.0.1:8080/health;
    proxy_set_header Host $host;
}
```

1Panel 中进入“网站 → 目标站点 → 配置 → 配置文件”添加规则，保存并重载 OpenResty。

### Caddy

```caddyfile
你的域名 {
    handle /v1/* {
        reverse_proxy 127.0.0.1:8080
    }
    handle /health {
        reverse_proxy 127.0.0.1:8080
    }
}
```

验证公网入口：

```bash
curl -fsS https://你的域名/health
curl -i https://你的域名/v1/ping
```

第二条命令不带密钥时应返回 `401`，说明 HTTPS、代理和鉴权均已生效。

## 连接客户端

在每台设备打开“设置 → 多端同步”：

```text
服务器地址：https://你的域名
同步密钥：SYNC_TOKEN 的完整 64 位值
设备名称：例如 iPhone、Windows-PC
自动同步：开启
```

服务器地址只填写基址，不要追加 `/v1/sync`。保存后点击“测试连接”。

若要使用服务器 AI，在“设置 → AI 助手”中选择“自托管服务器”，应用会复用当前同步地址和同步密钥；无需把模型 API Key 填到客户端。

## 同步行为

- 本地修改先落盘，再异步上传。
- 普通任务编辑经过约 100 毫秒合并窗口；开始、暂停、重置和切换番茄阶段会立即推送。
- 活跃客户端通过 `/v1/changes` 长轮询被服务端变更立即唤醒，不依赖五分钟定时轮询。
- iOS 锁屏后可能被系统挂起；此时 WidgetKit 无法维持长连接。若需要应用完全挂起后的后台秒级任务刷新，需要另行配置 APNs 静默推送及相应签名权限。
- 前台客户端保持一个最长 25 秒的休眠变更请求，修订号变化后才拉取完整状态。
- 5 分钟完整同步仅用于重连兜底。
- iOS 进入后台后可能被系统挂起；重新进入前台会立即补同步。

不要通过极短轮询或伪后台保活绕过 iOS 限制，这会增加耗电且不可靠。

## 更新

```bash
cd qingxu
git pull --ff-only
docker compose pull
docker compose up -d
docker compose ps
curl -fsS http://127.0.0.1:8080/health
```

清理清序镜像产生的旧悬空层：

```bash
docker image prune --filter label=org.opencontainers.image.title=qingxu-sync
```

不要在共享服务器上执行无范围限制的 `docker system prune -a --volumes`。

## 备份与恢复

默认数据文件是仓库目录下的 `data/store.json`。它包含任务、删除墓碑、番茄钟和 RSS 阅读状态，应按敏感数据保护。

### 一致性备份

```bash
cd qingxu
docker compose stop sync
tar -C data -czf "qingxu-sync-$(date +%F-%H%M%S).tar.gz" store.json
docker compose start sync
curl -fsS http://127.0.0.1:8080/health
```

### 恢复

```bash
cd qingxu
docker compose stop sync
tar -C data -xzf /安全路径/qingxu-sync-日期.tar.gz
sudo chown -R 65532:65532 data
sudo chmod 700 data
sudo chmod 600 data/store.json
docker compose up -d
curl -fsS http://127.0.0.1:8080/health
```

恢复前建议先保留当前 `store.json` 副本。不要让两个同步容器同时写同一目录。

## 安全清单

- `.env` 权限保持为 `600`，不得提交到 Git、截图或 Issue。
- 公网只开放 HTTPS，8080 仅绑定回环地址。
- 使用随机 256-bit 密钥，不复用其他网站密码。
- 定期备份 `store.json`，并保护备份文件权限。
- 容器以非 root 用户运行、根文件系统只读、移除全部 capabilities。
- 同步数据文件不是端到端加密容器，主机管理员仍能读取数据。
- 当前只支持单用户、单实例，不要将同一地址和密钥公开给他人。

## 排障

```bash
docker compose ps
docker compose logs --tail=100 sync
docker stats --no-stream
curl -i http://127.0.0.1:8080/health
curl -i https://你的域名/health
```

| 现象 | 处理 |
| --- | --- |
| 容器启动失败，提示 `SYNC_TOKEN` | 检查密钥是否恰好为 64 个十六进制字符 |
| `401 Unauthorized` | 客户端与服务器的同步密钥不一致 |
| `413 Request Entity Too Large` | 同时检查 `SYNC_MAX_BODY_BYTES` 和反向代理 `client_max_body_size` |
| `502 Bad Gateway` | 检查容器状态、`SYNC_LISTEN` 和 `127.0.0.1:8080` |
| `/health` 返回 `503` | 检查数据目录权限、只读挂载、磁盘空间和日志 |
| AI 返回未配置 | 填写 `AI_API_KEY` 后重新创建容器，并在客户端选择自托管模式 |
| 同步延迟明显 | 确认代理读取超时大于 25 秒，且没有缓存 `/v1/changes` |

仍无法定位时，先保存 `docker compose ps`、最近 100 行日志和两个健康检查结果，再进行下一步诊断。
