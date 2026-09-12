# Self-hosted sync

This guide deploys Qingxu's personal sync service on a Linux server. `todo.darker.one` hosts documentation only and is not required by the clients.

## Requirements

- A Linux server with Docker Engine and Docker Compose v2
- A domain name with a valid HTTPS certificate
- Nginx, Caddy, or 1Panel OpenResty as a reverse proxy

## Start the service

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

The health endpoint should return `{"status":"ok"}`. Save the token in a password manager; the server never returns it through an API.

## Environment

| Variable | Default | Purpose |
| --- | --- | --- |
| `SYNC_TOKEN` | none | Required 64-character hexadecimal sync token |
| `SYNC_LISTEN` | `127.0.0.1:8080` | Host listener; keep it on loopback |
| `SYNC_DATA_DIR` | `./data` | Persistent data directory |
| `SYNC_MAX_BODY_BYTES` | `2097152` | Maximum sync request size |
| `GOMEMLIMIT` | `48MiB` | Go runtime soft memory limit |
| `AI_BASE_URL` | OpenAI-compatible endpoint | Optional server-side AI endpoint |
| `AI_API_KEY` | empty | Leave empty to disable the AI proxy |
| `AI_MODEL` | `gpt-5.6-terra` | Model name sent to the endpoint |

## HTTPS reverse proxy

Keep port 8080 private. For Nginx or 1Panel OpenResty, add:

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

Verify the public endpoint:

```bash
curl -fsS https://your-domain.example/health
curl -i https://your-domain.example/v1/ping
```

The second command should return `401` without a token. This confirms that HTTPS, proxying, and authentication are active.

## Connect clients

Open **Settings → Multi-device sync** on every device and enter:

```text
Server URL: https://your-domain.example
Sync token: the complete SYNC_TOKEN
Device name: a unique name such as iPhone or Windows-PC
Automatic sync: enabled
```

Enter the base URL only; do not append `/v1/sync`. Save, then run the connection test.

## Update

```bash
cd qingxu
git pull --ff-only
docker compose pull
docker compose up -d
curl -fsS http://127.0.0.1:8080/health
```

## Backup

The default data file is `data/store.json`.

```bash
docker compose stop sync
tar -C data -czf "qingxu-sync-$(date +%F-%H%M%S).tar.gz" store.json
docker compose start sync
```

Protect `.env`, `store.json`, and backups as sensitive data. The current server is single-user and the data file is not end-to-end encrypted from the host administrator.

## Troubleshooting

```bash
docker compose ps
docker compose logs --tail=100 sync
docker stats --no-stream
curl -i http://127.0.0.1:8080/health
curl -i https://your-domain.example/health
```

- `401`: the client token and server token differ.
- `413`: raise both `SYNC_MAX_BODY_BYTES` and the proxy body limit.
- `502`: check the container, listener, and loopback address.
- Noticeable delay: keep `/v1/changes` uncached and set the proxy read timeout above 25 seconds.
