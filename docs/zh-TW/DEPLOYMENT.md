# 自託管同步

本指南用於在 Linux 伺服器部署清序的個人同步服務。`todo.darker.one` 只是文件網站，用戶端不依賴它。

## 準備

- 安裝 Docker Engine 與 Docker Compose v2 的 Linux 伺服器
- 已設定有效 HTTPS 憑證的網域
- Nginx、Caddy 或 1Panel OpenResty 反向代理

## 啟動服務

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
curl -fsS http://127.0.0.1:8080/health
echo "$TOKEN"
```

健康檢查應回傳 `{"status":"ok"}`。請把金鑰存入密碼管理器；伺服器不會透過 API 再次回傳它。

## 環境變數

| 變數 | 預設值 | 用途 |
| --- | --- | --- |
| `SYNC_TOKEN` | 無 | 必填的 64 位十六進位同步金鑰 |
| `SYNC_LISTEN` | `127.0.0.1:8080` | 主機監聽位址，建議只綁定回環介面 |
| `SYNC_DATA_DIR` | `./data` | 持久化資料目錄 |
| `SYNC_MAX_BODY_BYTES` | `2097152` | 單次同步請求大小上限 |
| `GOMEMLIMIT` | `48MiB` | Go 執行階段軟記憶體限制 |
| `AI_BASE_URL` | OpenAI 相容端點 | 選用的伺服器 AI 端點 |
| `AI_API_KEY` | 空 | 留空即停用 AI 代理 |
| `AI_MODEL` | `gpt-4.1-mini` | 模型名稱 |

## HTTPS 反向代理

不要將 8080 直接開放到網際網路。Nginx 或 1Panel OpenResty 可加入：

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
}
```

驗證公開入口：

```bash
curl -fsS https://你的網域/health
curl -i https://你的網域/v1/ping
```

第二條命令在沒有金鑰時應回傳 `401`，代表 HTTPS、代理和驗證均已生效。

## 連接用戶端

在每台裝置開啟「設定 → 多端同步」並填入：

```text
伺服器網址：https://你的網域
同步金鑰：完整的 SYNC_TOKEN
裝置名稱：例如 iPhone 或 Windows-PC
自動同步：開啟
```

網址只填基底網址，不要附加 `/v1/sync`。儲存後執行連線測試。

## 更新

```bash
cd qingxu
git pull --ff-only
docker compose pull
docker compose up -d
curl -fsS http://127.0.0.1:8080/health
```

## 備份

預設資料檔為 `data/store.json`：

```bash
docker compose stop sync
tar -C data -czf "qingxu-sync-$(date +%F-%H%M%S).tar.gz" store.json
docker compose start sync
```

請將 `.env`、`store.json` 和備份視為敏感資料。現有服務僅支援單一使用者，主機管理員仍可讀取資料檔。

## 疑難排解

```bash
docker compose ps
docker compose logs --tail=100 sync
docker stats --no-stream
curl -i http://127.0.0.1:8080/health
curl -i https://你的網域/health
```

- `401`：用戶端和伺服器的同步金鑰不一致。
- `413`：同時調高 `SYNC_MAX_BODY_BYTES` 與反向代理請求上限。
- `502`：檢查容器、監聽位址與回環介面。
- 同步延遲：確認 `/v1/changes` 沒有快取，且代理讀取逾時高於 25 秒。
