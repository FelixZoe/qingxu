#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  echo "Usage: qingxu-deploy <version> <git-sha> <staging-directory>" >&2
  exit 64
}

[[ $# -eq 3 ]] || usage

version="$1"
git_sha="$2"
staging="$(realpath "$3")"
short_sha="${git_sha:0:12}"

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || usage
[[ "$git_sha" =~ ^[0-9a-f]{40}$ ]] || usage
case "$staging" in
  /tmp/qingxu-deploy-*) ;;
  *) echo "Refusing unexpected staging directory: $staging" >&2; exit 65 ;;
esac

web_zip="$staging/Qingxu-${version}-Web.zip"
[[ -f "$web_zip" && ! -L "$web_zip" ]] || {
  echo "Missing regular Web artifact: $web_zip" >&2
  exit 66
}

web_base="/opt/1panel/www/sites/todo.darker.one"
web_release="$web_base/releases/${version}-${short_sha}"
sync_base="/opt/qingxu/sync"
sync_release="$sync_base/releases/$git_sha"
previous_web="$(readlink -f "$web_base/current" 2>/dev/null || true)"
previous_sync="$(readlink -f "$sync_base/current" 2>/dev/null || true)"
web_candidate=""
sync_candidate=""
source_workspace=""
activated_sync=false
switched_sync=false
switched_web=false
committed=false

validate_previous_path() {
  local path="$1"
  local base="$2"
  [[ -z "$path" || "$path" == "$base/releases/"* ]] || {
    echo "Current link escapes release directory: $path" >&2
    exit 67
  }
}
validate_previous_path "$previous_web" "$web_base"
validate_previous_path "$previous_sync" "$sync_base"

atomic_link() {
  local base="$1"
  local target="$2"
  local name="$3"
  local temporary="$base/.${name}-${short_sha}-$$"
  rm -f -- "$temporary"
  ln -s "$target" "$temporary"
  mv -Tf "$temporary" "$base/$name"
}

wait_for_sync() {
  for _ in {1..30}; do
    if curl --fail --silent --show-error http://127.0.0.1:8080/health >/dev/null; then
      return 0
    fi
    sleep 1
  done
  return 1
}

restore_previous_sync() {
  if [[ -n "$previous_sync" && -f "$previous_sync/docker-compose.yml" ]]; then
    local previous_tag
    previous_tag="$(basename "$previous_sync")"
    echo "Restoring previous sync release: $previous_tag" >&2
    (
      cd "$previous_sync"
      QINGXU_IMAGE_TAG="$previous_tag" docker compose -p qingxu up -d --no-build --remove-orphans
    )
    wait_for_sync
    atomic_link "$sync_base" "releases/$previous_tag" current
  else
    (
      cd "$sync_release"
      QINGXU_IMAGE_TAG="$git_sha" docker compose -p qingxu down
    ) || true
    rm -f -- "$sync_base/current"
  fi
}

restore_previous_web() {
  if [[ -n "$previous_web" ]]; then
    atomic_link "$web_base" "releases/$(basename "$previous_web")" current
  else
    rm -f -- "$web_base/current"
  fi
}

cleanup() {
  [[ -z "$web_candidate" ]] || rm -rf -- "$web_candidate"
  [[ -z "$sync_candidate" ]] || rm -rf -- "$sync_candidate"
  [[ -z "$source_workspace" ]] || rm -rf -- "$source_workspace"
  case "$staging" in
    /tmp/qingxu-deploy-*) rm -rf -- "$staging" ;;
  esac
}

rollback_on_error() {
  local status=$?
  trap - ERR
  if [[ "$committed" != true ]]; then
    if [[ "$switched_web" == true ]]; then
      restore_previous_web || echo "Web rollback failed" >&2
    fi
    if [[ "$activated_sync" == true ]]; then
      restore_previous_sync || echo "Sync rollback failed" >&2
    elif [[ "$switched_sync" == true ]]; then
      restore_previous_sync || echo "Sync link rollback failed" >&2
    fi
  fi
  exit "$status"
}
trap cleanup EXIT
trap rollback_on_error ERR

validate_web_release() {
  local release="$1"
  [[ -f "$release/index.html" && -f "$release/flutter_bootstrap.js" && -f "$release/version.json" ]]
  grep -Fq "\"version\":\"$version\"" "$release/version.json"
  grep -Fq "\"commit\":\"$git_sha\"" "$release/version.json"
}

mkdir -p "$web_base/releases" "$web_base/log" "$sync_base/releases" "$sync_base/data" "$sync_base/shared"
[[ -f "$sync_base/shared/.env" && ! -L "$sync_base/shared/.env" ]] || {
  echo "Missing protected sync environment: $sync_base/shared/.env" >&2
  exit 68
}
chown 65532:65532 "$sync_base/data"
chmod 0700 "$sync_base/data"
chmod 0600 "$sync_base/shared/.env"

# Fully stage and validate Web before touching the running sync container.
if [[ -d "$web_release" ]]; then
  validate_web_release "$web_release" || {
    echo "Existing immutable Web release is invalid: $web_release" >&2
    exit 69
  }
else
  if unzip -Z1 "$web_zip" | awk '
    /^\// || /(^|\/)\.\.(\/|$)/ { unsafe = 1 }
    END { exit unsafe ? 0 : 1 }
  '; then
    echo "Web artifact contains an unsafe path" >&2
    exit 70
  fi
  web_candidate="$(mktemp -d "$web_base/releases/.candidate-${version}-${short_sha}.XXXXXX")"
  unzip -q "$web_zip" -d "$web_candidate"
  validate_web_release "$web_candidate" || {
    echo "Web artifact is incomplete or has the wrong version" >&2
    exit 71
  }
  find "$web_candidate" -type d -exec chmod 0755 {} +
  find "$web_candidate" -type f -exec chmod 0644 {} +
  mv "$web_candidate" "$web_release"
  web_candidate=""
fi

# Fetch server code from the exact public Git commit. The deployment SSH user
# cannot inject a Dockerfile through the staging directory.
if [[ -d "$sync_release" ]]; then
  [[ -f "$sync_release/docker-compose.yml" && -f "$sync_release/Dockerfile" ]] || {
    echo "Existing immutable sync release is invalid: $sync_release" >&2
    exit 72
  }
else
  sync_candidate="$(mktemp -d "$sync_base/releases/.candidate-${short_sha}.XXXXXX")"
  source_workspace="$(mktemp -d /tmp/qingxu-source.XXXXXX)"
  source_archive="$source_workspace/source.tar.gz"
  curl --fail --silent --show-error --location \
    --proto '=https' --tlsv1.2 \
    "https://codeload.github.com/FelixZoe/qingxu/tar.gz/$git_sha" \
    -o "$source_archive"
  archive_root="$(tar -tzf "$source_archive" | awk -F/ '
    NR == 1 { first = $1 }
    END { print first }
  ')"
  [[ -n "$archive_root" && "$archive_root" != *..* ]] || {
    echo "Unexpected GitHub source archive" >&2
    exit 73
  }
  tar --no-same-owner --no-same-permissions -xzf "$source_archive" -C "$source_workspace"
  [[ -f "$source_workspace/$archive_root/services/sync/Dockerfile" ]] || {
    echo "Commit does not contain the sync service" >&2
    exit 74
  }
  cp -a "$source_workspace/$archive_root/services/sync/." "$sync_candidate/"
  ln -s "$sync_base/shared/.env" "$sync_candidate/.env"
  ln -s "$sync_base/data" "$sync_candidate/data"
  mv "$sync_candidate" "$sync_release"
  sync_candidate=""
fi

[[ "$(readlink -f "$sync_release/.env")" == "$sync_base/shared/.env" ]]
[[ "$(readlink -f "$sync_release/data")" == "$sync_base/data" ]]

if ! docker image inspect "qingxu-sync:$git_sha" >/dev/null 2>&1; then
  (
    cd "$sync_release"
    QINGXU_IMAGE_TAG="$git_sha" docker compose -p qingxu build sync
  )
fi

activated_sync=true
(
  cd "$sync_release"
  QINGXU_IMAGE_TAG="$git_sha" docker compose -p qingxu up -d --no-build --remove-orphans
)
if ! wait_for_sync; then
  QINGXU_IMAGE_TAG="$git_sha" docker compose -p qingxu -f "$sync_release/docker-compose.yml" logs --tail=100 sync >&2 || true
  false
fi

atomic_link "$sync_base" "releases/$git_sha" current
switched_sync=true
atomic_link "$web_base" "releases/${version}-${short_sha}" current
switched_web=true

production_version="$(curl --fail --silent --show-error https://todo.darker.one/version.json)"
grep -Fq "\"version\":\"$version\"" <<<"$production_version"
grep -Fq "\"commit\":\"$git_sha\"" <<<"$production_version"
curl --fail --silent --show-error https://todo.darker.one/health >/dev/null

committed=true

prune_releases() {
  local base="$1"
  local keep="$2"
  local remove_images="${3:-false}"
  local -a releases=()
  mapfile -t releases < <(find "$base" -mindepth 1 -maxdepth 1 -type d ! -name '.candidate-*' -printf '%T@ %p\n' | sort -nr | cut -d' ' -f2-)
  if (( ${#releases[@]} <= keep )); then
    return
  fi
  for release in "${releases[@]:keep}"; do
    case "$release" in
      "$base"/*)
        old_tag="$(basename "$release")"
        rm -rf -- "$release"
        if [[ "$remove_images" == true ]]; then
          docker image rm "qingxu-sync:$old_tag" >/dev/null 2>&1 || true
        fi
        ;;
      *) echo "Refusing to prune unexpected path: $release" >&2; return 1 ;;
    esac
  done
}

prune_releases "$web_base/releases" 3
prune_releases "$sync_base/releases" 3 true
docker image prune -f --filter "label=io.qingxu.component=sync" >/dev/null || true

echo "Deployed Qingxu v$version ($git_sha)"
