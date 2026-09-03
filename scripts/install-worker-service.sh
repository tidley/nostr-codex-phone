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

opencode_bin="${OPENCODE_BIN:-opencode}"
if [[ -z "${OPENCODE_BIN:-}" && -n "${HOME:-}" && -x "$HOME/.opencode/bin/opencode" ]]; then
  opencode_bin="$HOME/.opencode/bin/opencode"
fi

flutter_cache=""
if [[ -d /opt/flutter/bin/cache ]]; then
  flutter_cache=/opt/flutter/bin/cache
fi
github_config="${GH_CONFIG_DIR:-$HOME/.nostr-codex/gh/phone}"
if [[ ! -f "$github_config/hosts.yml" || ! -f "$github_config/gitconfig" ]]; then
  if [[ -n "${GH_CONFIG_DIR:-}" ]]; then
    echo "GitHub worker configuration is incomplete: $github_config" >&2
    exit 1
  fi
  github_config=""
fi

git_config="$state_dir/gitconfig"
{
  if [[ -n "$github_config" ]]; then
    printf '[include]\n\tpath = %s\n' "$github_config/gitconfig"
  fi
  printf '[user]\n\tname = Thomas Anderson\n\temail = noreply@github.com\n'
} >"$git_config"
chmod 600 "$git_config"

unit_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
unit="$unit_dir/nostr-codex-server.service"
update_script="$state_dir/bin/update-worker.sh"
update_unit="$unit_dir/nostr-codex-update.service"
update_timer="$unit_dir/nostr-codex-update.timer"
mkdir -p "$unit_dir"
mkdir -p "$(dirname "$update_script")"
install -m 755 "$(dirname "${BASH_SOURCE[0]}")/update-worker.sh" "$update_script"

cat >"$unit_dir/agent-workloads.slice" <<'UNIT'
[Slice]
MemoryHigh=12G
MemoryMax=14G
TasksMax=infinity
UNIT

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
Environment=OPENCODE_REAL_BIN=$opencode_bin
Environment=OPENCODE_BIN=$root/scripts/opencode-workdir-sandbox.sh
$(if [[ -n "$github_config" ]]; then printf 'Environment=GH_CONFIG_DIR=%s\n' "$github_config"; fi)
Environment=GIT_CONFIG_GLOBAL=$git_config
$(if [[ -n "$flutter_cache" ]]; then printf 'Environment=AGENT_WRITABLE_PATHS=%s\n' "$flutter_cache"; fi)
Environment=OPENCODE_AGENT=build
Environment=OPENCODE_SYSTEMD_SCOPE=1
Environment=OPENCODE_MAX_CONCURRENT_RUNS=10
Environment="GIT_AUTHOR_NAME=Thomas Anderson"
Environment=GIT_AUTHOR_EMAIL=noreply@github.com
Environment="GIT_COMMITTER_NAME=Thomas Anderson"
Environment=GIT_COMMITTER_EMAIL=noreply@github.com
Environment=AGENT_TIMEOUT_SECS=3600
# Record the STUN server and reflexive candidate selected for FIPS traversal.
Environment=RUST_LOG=info,nostr_codex_server=debug,fips::discovery::nostr::stun=debug,nostr_sdk=info,nostr=info
EnvironmentFile=-$env_file
Environment=NOSTR_CODEX_ENV_FILE=$env_file
Environment=PATH=$PATH
ExecStart=$worker
Restart=always
RestartSec=5
TimeoutStopSec=20
MemoryHigh=900M
MemoryMax=1G

[Install]
WantedBy=default.target
UNIT

cat >"$update_unit" <<UNIT
[Unit]
Description=Check for a verified Nostr Codex worker update
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
WorkingDirectory=$root
EnvironmentFile=-$env_file
Environment=CODEX_WORKDIR=$root
Environment=NOSTR_CODEX_WORKER=$worker
ExecStart=$update_script --apply
UNIT

cat >"$update_timer" <<'UNIT'
[Unit]
Description=Daily Nostr Codex worker update check

[Timer]
OnBootSec=10m
OnUnitActiveSec=24h
Persistent=true
RandomizedDelaySec=30m

[Install]
WantedBy=timers.target
UNIT

if [[ -z "${XDG_RUNTIME_DIR:-}" && -d "/run/user/$(id -u)" ]]; then
  export XDG_RUNTIME_DIR="/run/user/$(id -u)"
fi

systemctl --user daemon-reload
systemctl --user enable --now nostr-codex-server.service
systemctl --user restart nostr-codex-server.service
systemctl --user enable --now nostr-codex-update.timer
systemctl --user status nostr-codex-server.service --no-pager
