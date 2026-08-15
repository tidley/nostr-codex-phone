#!/usr/bin/env bash
# Downloads only signed worker releases, then switches the executable symlink
# atomically. A failed restart immediately restores the previous release.
set -euo pipefail

mode="${1:---apply}"
if [[ "$mode" != "--check" && "$mode" != "--apply" ]]; then
  echo "Usage: $0 [--check|--apply]" >&2
  exit 2
fi

worker_root="${CODEX_WORKDIR:-$PWD}"
state_dir="$worker_root/.nostr-codex"
worker_link="${NOSTR_CODEX_WORKER:-$state_dir/nostr-codex-worker-linux-x64}"
service="${NOSTR_CODEX_SERVICE:-nostr-codex-server.service}"
release_base="${NOSTR_CODEX_UPDATE_URL:-https://github.com/tidley/nostr-codex-phone/releases/latest/download}"
public_key="${NOSTR_CODEX_UPDATE_PUBLIC_KEY:-}"
health_timeout="${NOSTR_CODEX_UPDATE_HEALTH_TIMEOUT:-30}"
artifact="nostr-codex-worker-linux-x64"
releases_dir="$state_dir/releases"
previous_link="$state_dir/previous-worker"

for command in curl minisign sha256sum systemctl flock; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "$command is required for worker updates." >&2
    exit 1
  }
done
if [[ -z "$public_key" ]]; then
  echo "NOSTR_CODEX_UPDATE_PUBLIC_KEY must contain the Minisign public key." >&2
  exit 1
fi
if ! [[ "$health_timeout" =~ ^[1-9][0-9]*$ ]]; then
  echo "NOSTR_CODEX_UPDATE_HEALTH_TIMEOUT must be a positive number of seconds." >&2
  exit 1
fi

mkdir -p "$releases_dir"
exec 9>"$state_dir/worker-update.lock"
if ! flock -n 9; then
  echo "A worker update is already running." >&2
  exit 1
fi

tmp_dir="$(mktemp -d "$state_dir/.worker-update.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT
manifest="$tmp_dir/worker-update.json"
signature="$tmp_dir/worker-update.json.minisig"

download() {
  curl --fail --location --silent --show-error --retry 3 --connect-timeout 10 \
    --output "$2" "$1"
}

base="${release_base%/}"
download "$base/worker-update.json" "$manifest"
download "$base/worker-update.json.minisig" "$signature"
minisign -Vm "$manifest" -x "$signature" -P "$public_key" >/dev/null

version="$(sed -nE 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"([0-9A-Za-z._-]+)"[[:space:]]*,?[[:space:]]*$/\1/p' "$manifest")"
manifest_artifact="$(sed -nE 's/^[[:space:]]*"artifact"[[:space:]]*:[[:space:]]*"([A-Za-z0-9._-]+)"[[:space:]]*,?[[:space:]]*$/\1/p' "$manifest")"
expected_sha="$(sed -nE 's/^[[:space:]]*"sha256"[[:space:]]*:[[:space:]]*"([a-f0-9]{64})"[[:space:]]*,?[[:space:]]*$/\1/p' "$manifest")"
if [[ -z "$version" || "$manifest_artifact" != "$artifact" || -z "$expected_sha" ]]; then
  echo "Signed worker manifest has an invalid format." >&2
  exit 1
fi

release_dir="$releases_dir/$version"
release_worker="$release_dir/$artifact"
active_worker="$(readlink -f "$worker_link" 2>/dev/null || true)"
if [[ "$active_worker" == "$release_worker" ]]; then
  echo "Worker $version is already active."
  exit 0
fi

download "$base/$artifact" "$tmp_dir/$artifact"
actual_sha="$(sha256sum "$tmp_dir/$artifact" | cut -d' ' -f1)"
if [[ "$actual_sha" != "$expected_sha" ]]; then
  echo "Worker checksum does not match its signed manifest." >&2
  exit 1
fi
chmod 755 "$tmp_dir/$artifact"

if [[ "$mode" == "--check" ]]; then
  echo "Verified worker update $version is available."
  exit 0
fi

if [[ -e "$release_worker" ]]; then
  installed_sha="$(sha256sum "$release_worker" | cut -d' ' -f1)"
  if [[ "$installed_sha" != "$expected_sha" ]]; then
    echo "Installed release directory has an unexpected checksum: $release_dir" >&2
    exit 1
  fi
else
  mkdir -p "$release_dir"
  install -m 755 "$tmp_dir/$artifact" "$release_worker"
fi

# Existing installations use a regular binary. Preserve it as a rollback target
# before replacing that stable service path with a symlink.
previous_worker="$active_worker"
if [[ -f "$worker_link" && ! -L "$worker_link" ]]; then
  legacy_sha="$(sha256sum "$worker_link" | cut -d' ' -f1)"
  legacy_dir="$releases_dir/legacy-$legacy_sha"
  legacy_worker="$legacy_dir/$artifact"
  mkdir -p "$legacy_dir"
  if [[ ! -e "$legacy_worker" ]]; then
    install -m 755 "$worker_link" "$legacy_worker"
  fi
  previous_worker="$legacy_worker"
fi

swap_link() {
  local target="$1"
  local candidate="$state_dir/.${artifact}.next"
  ln -s "$target" "$candidate"
  mv -Tf "$candidate" "$worker_link"
}

wait_for_healthy_service() {
  local deadline=$((SECONDS + health_timeout))
  while (( SECONDS < deadline )); do
    if systemctl --user is-active --quiet "$service"; then
      sleep 1
    else
      return 1
    fi
  done
  systemctl --user is-active --quiet "$service"
}

swap_link "$release_worker"
if systemctl --user restart "$service" && wait_for_healthy_service; then
  if [[ -n "$previous_worker" && -e "$previous_worker" ]]; then
    candidate="$state_dir/.previous-worker.next"
    ln -s "$previous_worker" "$candidate"
    mv -Tf "$candidate" "$previous_link"
  fi
  echo "Activated worker $version ($actual_sha)."
  exit 0
fi

echo "Worker $version failed health checks; rolling back." >&2
if [[ -z "$previous_worker" || ! -e "$previous_worker" ]]; then
  echo "No previous worker is available for rollback." >&2
  exit 1
fi
swap_link "$previous_worker"
if ! systemctl --user restart "$service" || ! wait_for_healthy_service; then
  echo "Rollback failed. Manual intervention is required." >&2
  exit 1
fi
echo "Rollback restored $previous_worker." >&2
exit 1
