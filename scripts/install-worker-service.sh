#!/usr/bin/env bash
set -euo pipefail

root="$(pwd -P)"
worker="${NOSTR_CODEX_WORKER:-$root/nostr-codex-worker-linux-x64}"
if [[ ! -x "$worker" && -x "$root/nostr-codex-worker" ]]; then
  worker="$root/nostr-codex-worker"
fi
if [[ ! -x "$worker" ]]; then
  echo "Worker binary is not executable: $worker" >&2
  exit 1
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
EnvironmentFile=$root/.env.server
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
