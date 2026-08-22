#!/usr/bin/env bash
set -Eeuo pipefail

domain="todo.darker.one"
source_dir="/etc/letsencrypt/live/$domain"
target_dir="/opt/1panel/www/sites/$domain/ssl"

[[ -s "$source_dir/fullchain.pem" && -s "$source_dir/privkey.pem" ]] || {
  echo "Certificate files for $domain are missing" >&2
  exit 1
}

install -d -m 0700 "$target_dir"
install -m 0644 "$source_dir/fullchain.pem" "$target_dir/fullchain.pem"
install -m 0600 "$source_dir/privkey.pem" "$target_dir/privkey.pem"

openresty_container="${QINGXU_OPENRESTY_CONTAINER:-1Panel-openresty-CIJf}"
[[ "$(docker inspect --format '{{.State.Running}}' "$openresty_container" 2>/dev/null || true)" == true ]] || {
  echo "Configured 1Panel OpenResty container is not running: $openresty_container" >&2
  exit 1
}

docker exec "$openresty_container" openresty -t
docker exec "$openresty_container" openresty -s reload
