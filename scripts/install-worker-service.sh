#!/usr/bin/env bash
set -euo pipefail

root="$(pwd -P)"
state_dir="$root/.nostr-codex"
mkdir -p "$state_dir"

worker="${NOSTR_CODEX_WORKER:-$state_dir/nostr-codex-worker-linux-x64}"
if [[ ! -x "$worker" && -x "$state_dir/nostr-codex-worker" ]]; then
  worker="$state_dir/nostr-codex-worker"
fi
if [[ ! -x "$worker" && -x "$root/nostr-codex-worker-linux-x64" ]]; then
  worker="$root/nostr-codex-worker-linux-x64"
fi
if [[ ! -x "$worker" && -x "$root/nostr-codex-worker" ]]; then
  worker="$root/nostr-codex-worker"
fi
if [[ ! -x "$worker" ]]; then
  echo "Worker binary is not executable: $worker" >&2
  exit 1
fi

env_file="${NOSTR_CODEX_ENV_FILE:-$state_dir/.env.server}"
if [[ ! -f "$env_file" && -f "$root/.env.server" ]]; then
  env_file="$root/.env.server"
fi

unit_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
unit="$unit_dir/nostr-codex-server.service"
mkdir -p "$unit_dir"

cat >"$unit" <<UNIT
[Unit]
Description=Nostr Codex phone bridge
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
WorkingDirectory=$root
Environment=AGENT_BACKEND=opencode
Environment=AGENT_WORKDIR=$root
Environment=OPENCODE_URL=http://127.0.0.1:4096
Environment=OPENCODE_BIN=opencode
Environment=OPENCODE_AGENT=build
EnvironmentFile=-$env_file
Environment=NOSTR_CODEX_ENV_FILE=$env_file
Environment=PATH=$PATH
ExecStart=$worker
Restart=always
RestartSec=5
TimeoutStopSec=20

[Install]
WantedBy=default.target
UNIT

if [[ -z "${XDG_RUNTIME_DIR:-}" && -d "/run/user/$(id -u)" ]]; then
  export XDG_RUNTIME_DIR="/run/user/$(id -u)"
fi

systemctl --user daemon-reload
systemctl --user enable --now nostr-codex-server.service
systemctl --user restart nostr-codex-server.service
systemctl --user status nostr-codex-server.service --no-pager
