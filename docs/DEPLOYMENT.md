# 清序部署与运维

本文只说明 Web 与自托管同步服务。Windows 和 iOS 的安装文件由 GitHub Release 直接交付，不在这里重复安装说明。

## 环境模板与秘密

仓库提供两份可提交的模板：

- `services/sync/.env.example`：只运行同步服务；适合 1Panel/OpenResty 已存在的服务器。
- `deploy/.env.example`：Web 和同步服务都由 Docker Compose 运行。

真实文件必须命名为 `.env`。根目录 `.gitignore` 已忽略所有 `.env` 和数据目录，但提交前仍应使用 `git status` 检查。

同步密钥必须是 64 个十六进制字符：

```bash
openssl rand -hex 32
```

它相当于 256-bit 随机访问密钥。不要使用模板占位值、短密码或可记忆口令，也不要把它放进镜像、截图、Issue、Release 或 GitHub Actions 日志。

## 方案 A：完整 Docker 部署

适合一台没有现成 Web 服务器的主机。需要 Docker Engine 和 Docker Compose v2。

```bash
git clone https://github.com/FelixZoe/qingxu.git
cd qingxu/deploy
install -m 600 .env.example .env
nano .env
docker compose config --quiet
docker compose up -d --build
docker compose ps
curl http://127.0.0.1:8090/health
```

默认只监听 `127.0.0.1:8090`。请在 Caddy、Nginx 或 1Panel OpenResty 中把 HTTPS 域名反向代理到该地址，不要直接把 8090 暴露到公网。

Compose 包含：

- `web`：构建 Flutter Web 后由 Nginx 提供，96 MiB 内存上限；
- `sync`：Go 同步服务，64 MiB 内存上限；
- `qingxu-sync-data`：保存任务及删除墓碑的命名卷。

升级：

```bash
git pull --ff-only
cd deploy
docker compose up -d --build
docker compose ps
```

## 方案 B：1Panel/OpenResty + 轻量同步容器

这是 `todo.darker.one` 使用的生产形式。OpenResty 直接读取 Flutter Web 静态文件；同步服务只监听 `127.0.0.1:8080`。

目录约定：

```text
/opt/1panel/www/sites/todo.darker.one/
  current -> releases/<version>-<commit>/
  releases/
  log/
  ssl/

/opt/qingxu/sync/
  current -> releases/<commit>/
  releases/
  data/
  shared/.env
```

同步环境初始化：

```bash
sudo install -d -m 700 -o 65532 -g 65532 /opt/qingxu/sync/data
sudo install -d -m 700 /opt/qingxu/sync/shared
sudo install -m 600 services/sync/.env.example /opt/qingxu/sync/shared/.env
sudoedit /opt/qingxu/sync/shared/.env
```

生产 `.env` 应至少包含：

```dotenv
SYNC_TOKEN=<64 个十六进制字符>
SYNC_CORS_ORIGINS=https://todo.darker.one
SYNC_LISTEN=127.0.0.1:8080
SYNC_DATA_DIR=/opt/qingxu/sync/data
SYNC_MAX_BODY_BYTES=2097152
GOMEMLIMIT=48MiB
```

OpenResty 的 `/v1/` 与 `/health` 转发到 `127.0.0.1:8080`，其他路径使用 `try_files $uri $uri/ /index.html` 提供 Flutter 单页应用。`index.html`、Flutter bootstrap 和 service worker 必须使用 `no-cache`，带哈希的资源文件可以长期缓存。

HTTPS 证书使用 ACME/Certbot 自动续期。同步密钥只在 TLS 内作为 Bearer Token 发送，生产环境不得开放明文 HTTP 同步入口。

首次配置生产主机还需要安装固定部署入口、站点配置和证书续期钩子：

```bash
sudo apt-get update
sudo apt-get install -y curl unzip ca-certificates
sudo install -m 755 scripts/deploy/server.sh /usr/local/sbin/qingxu-deploy
sudo install -m 644 deploy/1panel/todo.darker.one.conf \
  /opt/1panel/www/conf.d/todo.darker.one.conf
sudo install -m 755 scripts/deploy/renew-todo-certificate.sh \
  /etc/letsencrypt/renewal-hooks/deploy/qingxu-todo-certificate.sh
sudo /etc/letsencrypt/renewal-hooks/deploy/qingxu-todo-certificate.sh
```

续期脚本默认操作生产容器 `1Panel-openresty-CIJf`，容器名变更时先以
`QINGXU_OPENRESTY_CONTAINER=<新容器名>` 运行并验证，再同步修改续期钩子。脚本会先执行 `openresty -t`，配置有效才重新加载。

GitHub Actions 不应直接登录管理账号。创建无交互 shell 的专用用户，只允许它执行固定 root helper：

```bash
sudo adduser --disabled-password --gecos '' qingxu-deploy
sudo install -d -m 700 -o qingxu-deploy -g qingxu-deploy /home/qingxu-deploy/.ssh
sudoedit /home/qingxu-deploy/.ssh/authorized_keys
sudo chown qingxu-deploy:qingxu-deploy /home/qingxu-deploy/.ssh/authorized_keys
sudo chmod 600 /home/qingxu-deploy/.ssh/authorized_keys
sudo visudo -f /etc/sudoers.d/qingxu-deploy
```

`authorized_keys` 中把 Actions 公钥写成 `restrict ssh-ed25519 ...`；sudoers 只保留：

```sudoers
qingxu-deploy ALL=(root) NOPASSWD: /usr/local/sbin/qingxu-deploy
```

部署私钥只保存为 GitHub Secret。不要把管理账号密钥复用到 CI，也不要授予部署用户任意 `docker` 或无参数 sudo 权限。

## GitHub Actions 自动部署

仓库工作流在所有测试和三端构建成功后执行生产部署。需要以下 Repository Secrets：

| Secret | 内容 |
| --- | --- |
| `DEPLOY_HOST` | 服务器地址 |
| `DEPLOY_USER` | 专用部署用户 |
| `DEPLOY_SSH_KEY` | 独立部署私钥，不复用个人管理密钥 |
| `DEPLOY_KNOWN_HOSTS` | 预先核验的服务器 SSH 主机公钥 |

部署过程：

1. 下载本次工作流生成的 Web ZIP；
2. 只上传到本次提交专用临时目录，不接受上传的脚本或 Dockerfile；
3. root helper 从公开 GitHub 仓库下载并校验本次精确 commit 的同步服务源码；
4. 校验 ZIP 路径与版本标识，创建不可变 Web release 目录；
5. 构建并探活新的同步容器，失败时恢复上一版本；
6. 原子切换 `current` 软链接；
7. 只保留最近三个 Web 与同步服务版本，并只清理带清序标签的悬空镜像；
8. 从公网验证 `/health` 与 `version.json` 中的精确版本和 commit。

工作流不会运行全局 `docker system prune`，也不会删除 1Panel 中其他项目的镜像、容器或数据卷。

## 健康检查与排障

```bash
curl -fsS https://todo.darker.one/health
sudo docker compose -p qingxu -f /opt/qingxu/sync/current/docker-compose.yml ps
sudo docker compose -p qingxu -f /opt/qingxu/sync/current/docker-compose.yml logs --tail=100 sync
sudo docker stats --no-stream
```

预期健康响应：

```json
{"status":"ok"}
```

常见状态：

- `401`：服务器正常，但同步密钥错误；
- `403`：Web Origin 不在 `SYNC_CORS_ORIGINS`；
- `413`：单次请求超过 `SYNC_MAX_BODY_BYTES`；
- `502`：OpenResty 无法连接本机同步容器；
- 容器 `unhealthy`：检查 `.env` 密钥格式、数据目录权限和磁盘空间。

## 备份与恢复

同步不是备份。任务数据位于 `/opt/qingxu/sync/data/store.json`，备份文件包含全部任务和删除墓碑，应按敏感数据保存。

一致性备份：

```bash
cd /opt/qingxu/sync/current
sudo docker compose -p qingxu stop sync
sudo tar -C /opt/qingxu/sync/data -czf /opt/qingxu/qingxu-sync-$(date +%F-%H%M%S).tar.gz store.json
sudo docker compose -p qingxu start sync
curl -fsS http://127.0.0.1:8080/health
```

恢复前先停止同步服务，将备份中的 `store.json` 解压回数据目录，然后修复权限：

```bash
sudo chown 65532:65532 /opt/qingxu/sync/data/store.json
sudo chmod 600 /opt/qingxu/sync/data/store.json
sudo docker compose -p qingxu -f /opt/qingxu/sync/current/docker-compose.yml up -d
```

## 手动回滚

列出保留版本：

```bash
ls -lt /opt/1panel/www/sites/todo.darker.one/releases
ls -lt /opt/qingxu/sync/releases
```

Web 回滚只需把 `current` 原子切换到选定目录。同步服务回滚后还要从该目录重新执行 `docker compose up -d --build`。不要回滚或直接编辑 `data/store.json` 的格式版本；数据恢复应使用同版本备份。
