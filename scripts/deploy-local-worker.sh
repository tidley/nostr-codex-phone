#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
worker_root="${CODEX_WORKDIR:-$(dirname "$repo_root")}"
source_worker="$repo_root/rust/target/release/nostr-codex-server"
target_worker="${NOSTR_CODEX_WORKER:-$worker_root/.nostr-codex/nostr-codex-worker-linux-x64}"
service="${NOSTR_CODEX_SERVICE:-nostr-codex-server.service}"

if [[ ! -x "$source_worker" ]]; then
  echo "Missing release worker: $source_worker" >&2
  echo "Run: cargo build --release --manifest-path rust/Cargo.toml --bin nostr-codex-server" >&2
  exit 1
fi
if [[ ! -d "$(dirname "$target_worker")" ]]; then
  echo "Missing worker state directory: $(dirname "$target_worker")" >&2
  echo "Install the worker service before deploying a local build." >&2
  exit 1
fi

exec_start="$(systemctl --user show -p ExecStart --value "$service")"
if [[ "$exec_start" != *"$target_worker"* ]]; then
  echo "Service $service does not execute $target_worker" >&2
  echo "Refusing to copy a build to an inactive worker path." >&2
  exit 1
fi

install -m 755 "$source_worker" "$target_worker"
if [[ "$(sha256sum "$source_worker" | cut -d' ' -f1)" != "$(sha256sum "$target_worker" | cut -d' ' -f1)" ]]; then
  echo "Worker checksum verification failed" >&2
  exit 1
fi

systemctl --user restart "$service"
systemctl --user is-active --quiet "$service"
echo "Deployed and restarted $service with $(sha256sum "$target_worker" | cut -d' ' -f1)"
