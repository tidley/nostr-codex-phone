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
flutter_cache=""
if [[ -d /opt/flutter/bin/cache ]]; then
  flutter_cache=/opt/flutter/bin/cache
fi
flutter_bin="$(command -v flutter 2>/dev/null || true)"
if [[ -z "$flutter_bin" && -x /opt/flutter/bin/flutter ]]; then
  flutter_bin=/opt/flutter/bin/flutter
fi
flutter_root=""
if [[ -n "$flutter_bin" && -x "$flutter_bin" ]]; then
  flutter_root="$(dirname "$(dirname "$(realpath "$flutter_bin")")")"
fi
rustup_bin="$(command -v rustup 2>/dev/null || true)"
rustup_home="${RUSTUP_HOME:-$HOME/.rustup}"
rust_tool_bin=""
if [[ -n "$rustup_bin" && -x "$rustup_bin" && -d "$rustup_home" ]]; then
  rust_tool_bin="$(dirname "$(realpath "$rustup_bin")")"
  rustup_home="$(realpath "$rustup_home")"
fi
shared_pictures=""
if [[ -d /tmp/pics ]]; then
  shared_pictures=/tmp/pics
fi
node_bin="$(command -v node 2>/dev/null || true)"
node_runtime=""
if [[ -n "$node_bin" && "$node_bin" == /* && -x "$node_bin" ]]; then
  node_runtime="$(dirname "$(dirname "$(realpath "$node_bin")")")"
fi
skill_bind_paths=()
for path in "$HOME/.opencode/skills" "$HOME/.agents/skills"; do
  [[ -d "$path" ]] && skill_bind_paths+=("$path")
done
space_home="$state_dir/home"
mkdir -p -- "$space_home/.config" "$space_home/.cache" "$space_home/.local/share/opencode"
mkdir -p -- "$space_home/.config/opencode"
mkdir -p -- "$space_home/.cargo"
cat >"$space_home/.gitconfig" <<'GITCONFIG'
[user]
	name = Thomas Anderson
	email = noreply@github.com
GITCONFIG
chmod 600 "$space_home/.gitconfig"
for config_file in opencode.json opencode.jsonc tui.json; do
  if [[ -f "$HOME/.config/opencode/$config_file" ]]; then
    install -m 600 "$HOME/.config/opencode/$config_file" "$space_home/.config/opencode/$config_file"
  fi
done
if [[ -f "$HOME/.local/share/opencode/auth.json" ]]; then
  # Keep credentials private to this worker's state while its session database
  # remains independent from every other worker.
  install -m 600 "$HOME/.local/share/opencode/auth.json" "$space_home/.local/share/opencode/auth.json"
fi

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
  printf 'CARGO_HOME=%s\n' "$(env_value "$space_home/.cargo")"
  if [[ -n "$rustup_home" && -n "$rust_tool_bin" ]]; then
    printf 'RUSTUP_HOME=%s\n' "$(env_value "$rustup_home")"
    printf 'RUST_TOOL_BIN=%s\n' "$(env_value "$rust_tool_bin")"
  fi
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
Environment="GIT_AUTHOR_NAME=Thomas Anderson"
Environment=GIT_AUTHOR_EMAIL=noreply@github.com
Environment="GIT_COMMITTER_NAME=Thomas Anderson"
Environment=GIT_COMMITTER_EMAIL=noreply@github.com
Environment=AGENT_TIMEOUT_SECS=3600
Environment=PATH=$(if [[ -n "$node_runtime" ]]; then printf '%s/bin:' "$(systemd_escape "$node_runtime")"; fi)$(if [[ -n "$flutter_root" ]]; then printf '%s/bin:' "$(systemd_escape "$flutter_root")"; fi)$(if [[ -n "$rust_tool_bin" ]]; then printf '%s:' "$(systemd_escape "$rust_tool_bin")"; fi)/usr/local/bin:/usr/bin:/bin
$(if [[ -n "$flutter_cache" ]]; then printf 'Environment=AGENT_WRITABLE_PATHS=%s\n' "$(systemd_escape "$flutter_cache")"; fi)
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
$(if [[ -n "$flutter_cache" ]]; then printf 'ReadWritePaths=%s\n' "$(systemd_escape "$flutter_cache")"; fi)
$(if [[ -n "$shared_pictures" ]]; then printf 'BindReadOnlyPaths=%s\n' "$(systemd_escape "$shared_pictures")"; fi)
$(if [[ -n "$node_runtime" ]]; then printf 'BindReadOnlyPaths=%s\n' "$(systemd_escape "$node_runtime")"; fi)
$(if [[ -n "$flutter_root" ]]; then printf 'BindReadOnlyPaths=%s\n' "$(systemd_escape "$flutter_root")"; fi)
$(if [[ -n "$rust_tool_bin" ]]; then printf 'BindReadOnlyPaths=%s\n' "$(systemd_escape "$rust_tool_bin")"; fi)
$(if [[ -n "$rustup_home" && -n "$rust_tool_bin" ]]; then printf 'BindReadOnlyPaths=%s\n' "$(systemd_escape "$rustup_home")"; fi)
$(for path in "${skill_bind_paths[@]}"; do printf 'BindReadOnlyPaths=%s\n' "$(systemd_escape "$path")"; done)
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
