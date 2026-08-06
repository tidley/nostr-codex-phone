#!/usr/bin/env bash
set -euo pipefail

# Install one isolated worker service for a named, existing workspace.
# Usage: scripts/install-worker-space.sh --name <space-name> --root <path>

usage() {
  echo "Usage: ${0##*/} --name <space-name> --root <path>" >&2
  exit 2
}

name=""
root_input=""
while (($#)); do
  case "$1" in
    --name)
      (($# >= 2)) || usage
      name="$2"
      shift 2
      ;;
    --root)
      (($# >= 2)) || usage
      root_input="$2"
      shift 2
      ;;
    --help|-h)
      usage
      ;;
    *)
      usage
      ;;
  esac
done

[[ -n "$name" && -n "$root_input" ]] || usage
if [[ ! "$name" =~ ^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$ ]]; then
  echo "Invalid space name: use 1-64 letters, digits, underscores, or hyphens." >&2
  exit 2
fi
if [[ ! -d "$root_input" ]]; then
  echo "Worker root is not an existing directory: $root_input" >&2
  exit 2
fi

root="$(realpath -e -- "$root_input")"
[[ -d "$root" ]] || {
  echo "Worker root is not a directory: $root" >&2
  exit 2
}
state_dir="$root/.nostr-codex"
mkdir -p -- "$state_dir"

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
worker="$(realpath -e -- "$worker")"

config_root="${XDG_CONFIG_HOME:-${HOME:?HOME or XDG_CONFIG_HOME is required}/.config}"
unit_dir="$config_root/systemd/user"
env_dir="$config_root/nostr-codex/spaces"
unit_name="nostr-codex-space-$name.service"
unit="$unit_dir/$unit_name"
space_env="$env_dir/$name.env"
worker_env="$state_dir/.env.server"
mkdir -p -- "$unit_dir" "$env_dir"

opencode_bin="${OPENCODE_BIN:-opencode}"
if [[ -z "${OPENCODE_BIN:-}" && -n "${HOME:-}" && -x "$HOME/.opencode/bin/opencode" ]]; then
  opencode_bin="$HOME/.opencode/bin/opencode"
fi
opencode_bind=""
if [[ "$opencode_bin" == /* ]]; then
  opencode_bin="$(realpath -e -- "$opencode_bin")"
  opencode_bind="$opencode_bin"
fi
space_home="$state_dir/home"
mkdir -p -- "$space_home/.config" "$space_home/.cache" "$space_home/.local/share"

# Escape values for systemd's unit-file parser without using shell quoting.
systemd_escape() {
  local LC_ALL=C value="$1" escaped="" char hex i
  for ((i = 0; i < ${#value}; i++)); do
    char="${value:i:1}"
    case "$char" in
      [A-Za-z0-9/._:-]) escaped+="$char" ;;
      '%') escaped+='%%' ;;
      *)
        printf -v hex '%02x' "'$char"
        escaped+="\\x$hex"
        ;;
    esac
  done
  printf '%s' "$escaped"
}

# EnvironmentFile accepts shell-like quotes; reject control characters instead.
env_value() {
  local value="$1"
  [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] || {
    echo "Path contains unsupported control characters." >&2
    exit 2
  }
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  printf '"%s"' "$value"
}

umask 077
{
  printf 'AGENT_WORKDIR=%s\n' "$(env_value "$root")"
  printf 'CODEX_WORKDIR=%s\n' "$(env_value "$root")"
  printf 'NOSTR_CODEX_ENV_FILE=%s\n' "$(env_value "$worker_env")"
  printf 'OPENCODE_BIN=%s\n' "$(env_value "$opencode_bin")"
  printf 'HOME=%s\n' "$(env_value "$space_home")"
  printf 'XDG_CONFIG_HOME=%s\n' "$(env_value "$space_home/.config")"
  printf 'XDG_CACHE_HOME=%s\n' "$(env_value "$space_home/.cache")"
  printf 'XDG_DATA_HOME=%s\n' "$(env_value "$space_home/.local/share")"
} >"$space_env"

cat >"$unit" <<UNIT
[Unit]
Description=Nostr Codex worker space $name
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
WorkingDirectory=$(systemd_escape "$root")
EnvironmentFile=$(systemd_escape "$space_env")
EnvironmentFile=-$(systemd_escape "$worker_env")
Environment=AGENT_BACKEND=opencode
Environment=OPENCODE_AGENT=build
# Child processes must inherit this unit's mount namespace.
Environment=OPENCODE_SYSTEMD_SCOPE=0
Environment=OPENCODE_MAX_CONCURRENT_RUNS=10
Environment=PATH=/usr/local/bin:/usr/bin:/bin
ExecStart=$(systemd_escape "$worker")
Restart=always
RestartSec=5
TimeoutStopSec=20
MemoryHigh=900M
MemoryMax=1G
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=tmpfs
BindPaths=$(systemd_escape "$root")
ReadWritePaths=$(systemd_escape "$root")
$(if [[ -n "$opencode_bind" ]]; then printf 'BindReadOnlyPaths=%s\n' "$(systemd_escape "$opencode_bind")"; fi)

[Install]
WantedBy=default.target
UNIT

if [[ -z "${XDG_RUNTIME_DIR:-}" && -d "/run/user/$(id -u)" ]]; then
  export XDG_RUNTIME_DIR="/run/user/$(id -u)"
fi

systemctl --user daemon-reload
systemctl --user enable --now "$unit_name"
systemctl --user status "$unit_name" --no-pager
