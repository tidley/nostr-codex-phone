#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bridge_dir="$(cd "$script_dir/.." && pwd)"
repo_dir="$(cd "${1:-$PWD}" && pwd)"
service_name="${2:-nostr-codex-$(basename "$repo_dir")}"
env_file="${3:-$repo_dir/.env.server}"
uid="$(id -u)"

service_name="${service_name%.service}"
service_name="$(printf '%s' "$service_name" | tr -c 'A-Za-z0-9_.@-' '-')"
unit_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
unit_file="$unit_dir/$service_name.service"
binary="$bridge_dir/rust/target/debug/nostr-codex-server"

if [[ ! -f "$env_file" ]]; then
  mkdir -p "$(dirname "$env_file")"
  touch "$env_file"
  chmod 600 "$env_file"
  echo "created empty env file: $env_file"
fi

if [[ ! -x "$binary" ]]; then
  echo "missing server binary: $binary" >&2
  echo "build it with: cargo build --manifest-path $bridge_dir/rust/Cargo.toml --bin nostr-codex-server" >&2
  exit 1
fi

mkdir -p "$unit_dir"
cat >"$unit_file" <<EOF
[Unit]
Description=Nostr Codex phone bridge ($repo_dir)
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
WorkingDirectory=$repo_dir
EnvironmentFile=$env_file
Environment=PATH=$HOME/.nvm/versions/node/v24.12.0/bin:$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
Environment=CODEX_WORKDIR=$repo_dir
Environment=CODEX_MEMORY_DB=$repo_dir/.nostr-codex-memory.sqlite3
Environment=NOSTR_CODEX_ENV_FILE=$env_file
ExecStart=$binary
Restart=always
RestartSec=5
TimeoutStopSec=20

[Install]
WantedBy=default.target
EOF

loginctl enable-linger "$USER" >/dev/null 2>&1 || true
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$uid}"

systemctl --user daemon-reload
systemctl --user enable --now "$service_name.service"

echo "installed user service: $service_name.service"
echo "unit: $unit_file"
echo "status: systemctl --user status $service_name.service"
echo "logs: journalctl --user -u $service_name.service -f"
