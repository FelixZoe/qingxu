# 清序同步服务部署

本文只部署清序的自托管同步后台。iOS、Android、Windows 与 macOS 客户端从 GitHub Release 获取；`todo.darker.one` 只是独立的产品预览站。

## 准备

- 一台安装了 Docker Engine 与 Docker Compose v2 的 Linux 服务器
- 一个已解析到服务器的域名
- Nginx、Caddy 或 1Panel OpenResty，用于 HTTPS 和反向代理

同步密钥必须由安全随机数生成：

```bash
openssl rand -hex 32
```

结果是 64 个十六进制字符，即 256-bit 随机密钥。服务端不会把密钥返回给客户端；请自行安全保存。

## 启动

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

默认只监听 `127.0.0.1:8080`，不要把没有 TLS 的 8080 端口开放到公网。

## 1Panel / Nginx 反向代理

让网站根路径继续展示你自己的页面，只把同步接口转发给 Go 服务：

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

在 1Panel 中可进入“网站 → 配置 → 反向代理/配置文件”加入以上规则。网站必须启用有效 HTTPS 证书，然后检查：

```bash
curl -fsS https://你的域名/health
```

## 客户端配置

在每一台设备打开“设置 → 多端同步”：

```text
服务器地址：https://你的域名
同步密钥：SYNC_TOKEN 的完整 64 位值
设备名称：任意易识别名称
自动同步：开启
```

服务器地址不要附加 `/v1/sync`。保存后点击“测试连接”；之后任务、项目字段、完成状态、备注、时间信息与番茄钟状态会自动同步。

客户端保持一个最长 25 秒的低成本变更等待请求。任意设备修改后，服务端只广播新的修订号，其他前台设备再拉取完整数据；没有变化时不会反复上传任务。番茄钟操作约 250ms 后推送，普通任务继续防抖合并上传，5 分钟完整同步仅作断线容错。设备时钟存在小幅偏差时，客户端使用响应中的 `serverTime` 校准同一个 `endsAt` 倒计时。

iOS 进入后台后可能被系统挂起，不能依赖普通网络请求常驻；重新进入前台时会立即补同步。不要通过缩短轮询或后台保活绕过系统限制，这会明显增加耗电并可能影响审核。

## 更新

```bash
cd qingxu
git pull --ff-only
docker compose pull
docker compose up -d
docker compose ps
curl -fsS http://127.0.0.1:8080/health
```

只清理清序镜像的旧悬空层，不影响 1Panel 中其他项目：

```bash
docker image prune --filter label=org.opencontainers.image.title=qingxu-sync
```

不要执行无范围限制的 `docker system prune -a --volumes`。

## 数据、备份与恢复

默认数据文件是仓库目录下的 `data/store.json`，可在 `.env` 中用绝对路径修改 `SYNC_DATA_DIR`。文件包含全部任务、删除墓碑与番茄钟状态，应按敏感数据保护。

一致性备份：

```bash
cd qingxu
docker compose stop sync
tar -C data -czf "qingxu-sync-$(date +%F-%H%M%S).tar.gz" store.json
docker compose start sync
curl -fsS http://127.0.0.1:8080/health
```

恢复：

```bash
cd qingxu
docker compose stop sync
tar -C data -xzf /安全路径/qingxu-sync-日期.tar.gz
chown -R 65532:65532 data
chmod 700 data
chmod 600 data/store.json
docker compose up -d
```

## 安全边界

- `.env` 权限保持为 `600`，不得提交到 Git、放进截图或复制到 Issue。
- 公网只开放 HTTPS；8080 仅监听回环地址。
- 容器以非 root 用户运行，根文件系统只读，内存上限 64 MiB，Go 软限制 48 MiB。
- 当前模型是单用户、单同步实例。不要让多个服务实例同时写同一个 `store.json`。
- Bearer 密钥保护接口访问，数据文件本身不是端到端加密文件；主机权限和备份仍需保护。

## 排障

```bash
docker compose ps
docker compose logs --tail=100 sync
docker stats --no-stream
curl -i https://你的域名/health
```

| 状态 | 含义 |
| --- | --- |
| `401` | 同步密钥不一致 |
| `413` | 请求超过 `SYNC_MAX_BODY_BYTES` |
| `502` | 反向代理无法连接 `127.0.0.1:8080` |
| `unhealthy` | 检查密钥格式、数据目录权限、磁盘空间和容器日志 |
