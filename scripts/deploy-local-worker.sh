#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
worker_root="${CODEX_WORKDIR:-$(dirname "$repo_root")}"
source_worker="$repo_root/rust/target/release/nostr-codex-server"
target_worker="${NOSTR_CODEX_WORKER:-$worker_root/.nostr-codex/nostr-codex-worker-linux-x64}"
service="${NOSTR_CODEX_SERVICE:-nostr-codex-server.service}"
registry="$worker_root/.nostr-codex/workers.json"

# Non-interactive shells often omit the user-session bus environment. Deploying
# must restart the service, so never replace the live binary without that bus.
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"
if [[ ! -S "$XDG_RUNTIME_DIR/bus" ]]; then
  echo "Cannot reach the user systemd bus at $XDG_RUNTIME_DIR/bus." >&2
  echo "Manual intervention required: run this script from the worker user's desktop session." >&2
  echo "That session must export XDG_RUNTIME_DIR and DBUS_SESSION_BUS_ADDRESS before deployment." >&2
  exit 1
fi

if [[ ! -x "$source_worker" ]]; then
  echo "Missing release worker: $source_worker" >&2
  echo "Run: cargo build --release --manifest-path rust/Cargo.toml --bin nostr-codex-server" >&2
  exit 1
fi
workers=("$service:$target_worker")
if [[ -f "$registry" ]]; then
  command -v jq >/dev/null || {
    echo "jq is required to deploy registered worker spaces." >&2
    exit 1
  }
  while IFS=$'\t' read -r name workdir; do
    [[ -n "$name" && -n "$workdir" ]] || continue
    workers+=("nostr-codex-space-$name.service:$workdir/.nostr-codex/nostr-codex-worker-linux-x64")
  done < <(jq -r '.workers[]? | [.name, .workdir] | @tsv' "$registry")
fi

# Validate every unit before replacing any live binary. This avoids a partial
# deployment when a registered worker has not been installed as a service.
for worker in "${workers[@]}"; do
  unit="${worker%%:*}"
  binary="${worker#*:}"
  if [[ ! -d "$(dirname "$binary")" ]]; then
    echo "Missing worker state directory: $(dirname "$binary")" >&2
    exit 1
  fi
  exec_start="$(systemctl --user show -p ExecStart --value "$unit")"
  if [[ "$exec_start" != *"$binary"* ]]; then
    echo "Service $unit does not execute $binary" >&2
    echo "Install the worker service before deploying a local build." >&2
    exit 1
  fi
done

checksum="$(sha256sum "$source_worker" | cut -d' ' -f1)"
for worker in "${workers[@]}"; do
  unit="${worker%%:*}"
  binary="${worker#*:}"
  install -m 755 "$source_worker" "$binary"
  if [[ "$checksum" != "$(sha256sum "$binary" | cut -d' ' -f1)" ]]; then
    echo "Worker checksum verification failed for $binary" >&2
    exit 1
  fi
  systemctl --user restart "$unit"
  systemctl --user is-active --quiet "$unit"
  echo "Deployed and restarted $unit with $checksum"
done
