#!/usr/bin/env bash
set -euo pipefail

workdir="$(pwd -P)"
read_root="${AGENT_READ_ROOT:-${AGENT_WORKDIR:-$(dirname "$workdir")}}"
read_root="$(realpath "$read_root")"
real_bin="${OPENCODE_REAL_BIN:-${OPENCODE_BIN_REAL:-opencode}}"
if [[ "$real_bin" != /* ]]; then
  real_bin="$(command -v "$real_bin")"
fi
real_bin="$(realpath "$real_bin")"
node_bin="$(command -v node 2>/dev/null || true)"
node_runtime=""
if [[ -n "$node_bin" && "$node_bin" == /* && -x "$node_bin" ]]; then
  node_runtime="$(dirname "$(dirname "$(realpath "$node_bin")")")"
fi
flutter_bin="$(command -v flutter 2>/dev/null || true)"
flutter_root=""
if [[ -n "$flutter_bin" && "$flutter_bin" == /* && -x "$flutter_bin" ]]; then
  flutter_root="$(dirname "$(dirname "$(realpath "$flutter_bin")")")"
fi

case "$workdir/" in
  "$read_root/"*) ;;
  *)
    printf 'Agent working directory must be inside read root: %s\n' "$read_root" >&2
    exit 1
    ;;
esac

# Start with an empty filesystem. System runtime paths are mounted separately;
# project files are visible only through the declared read root below.
declare -A sandbox_dirs=()
args=(
  --die-with-parent
  --tmpfs /
  --dir /usr
  --ro-bind /usr /usr
  --dir /bin
  --ro-bind /bin /bin
  --dir /lib
  --ro-bind /lib /lib
  --dir /lib64
  --ro-bind /lib64 /lib64
  --dir /etc
  --ro-bind /etc /etc
  --tmpfs /tmp
  --dev /dev
  --proc /proc
)

add_destination_path() {
  local path="$1"
  local base=""
  case "$path/" in
    "$HOME/"*) base="$HOME" ;;
    /tmp/*) base=/tmp ;;
    /opt/*) base=/opt ;;
    *) return ;;
  esac

  local suffix="${path#"$base"/}"
  local current="$base"
  IFS=/ read -r -a segments <<<"$suffix"
  for segment in "${segments[@]}"; do
    [[ -n "$segment" ]] || continue
    current="$current/$segment"
    [[ -n "${sandbox_dirs[$current]:-}" ]] && continue
    sandbox_dirs["$current"]=1
    args+=(--dir "$current")
  done
}

add_destination_path "$read_root"
add_destination_path "$workdir"
add_destination_path "$(dirname "$real_bin")"
args+=(--ro-bind "$read_root" "$read_root")
args+=(--bind "$workdir" "$workdir")
args+=(--ro-bind "$real_bin" "$real_bin")
if [[ -n "$node_runtime" ]]; then
  add_destination_path "$node_runtime"
  args+=(--ro-bind "$node_runtime" "$node_runtime")
fi
if [[ -n "$flutter_root" ]]; then
  add_destination_path "$flutter_root"
  args+=(--ro-bind "$flutter_root" "$flutter_root")
fi

# Photos shared through the phone are available to every conversation without
# granting access to the rest of the host's temporary directory.
if [[ -d /tmp/pics ]]; then
  add_destination_path /tmp/pics
  args+=(--ro-bind /tmp/pics /tmp/pics)
fi

# Installed skills are executable guidance, not workspace content. Expose only
# their directories so a scoped conversation cannot inspect the rest of $HOME.
for path in "$HOME/.opencode/skills" "$HOME/.agents/skills"; do
    [[ -d "$path" ]] || continue
    add_destination_path "$path"
    args+=(--ro-bind "$path" "$path")
done

# GitHub authentication is provisioned outside the sandbox for one worker
# identity. It is read-only here and must stay below HOME like other mounted
# worker state.
if [[ -n "${GH_CONFIG_DIR:-}" ]]; then
    github_config="$(realpath "$GH_CONFIG_DIR")"
    case "$github_config/" in
        "$HOME/"*) ;;
        *)
            printf 'GitHub configuration must be inside HOME: %s\n' "$github_config" >&2
            exit 1
            ;;
    esac
    add_destination_path "$github_config"
    args+=(--ro-bind "$github_config" "$github_config")
fi

# OpenCode keeps its configuration, credentials, cache, and session database
# outside the code tree. Mount only those application directories read-write.
for path in \
  "$HOME/.config/opencode" \
  "$HOME/.cache/opencode" \
  "$HOME/.local/share/opencode" \
  "$HOME/.local/state/opencode"; do
  [[ -d "$path" ]] || continue
  add_destination_path "$path"
  args+=(--bind "$path" "$path")
done

# Build tools can need a small writable cache outside the workspace. The
# service owner explicitly opts paths in through AGENT_WRITABLE_PATHS.
if [[ -n "${AGENT_WRITABLE_PATHS:-}" ]]; then
  IFS=: read -r -a writable_paths <<<"$AGENT_WRITABLE_PATHS"
  for path in "${writable_paths[@]}"; do
    [[ -n "$path" ]] || continue
    if [[ "$path" != /* || ! -d "$path" ]]; then
      printf 'Writable agent path must be an existing absolute directory: %s\n' "$path" >&2
      exit 1
    fi
    path="$(realpath "$path")"
    add_destination_path "$path"
    args+=(--bind "$path" "$path")
  done
fi

mkdir -p /tmp/opencode
add_destination_path /tmp/opencode
args+=(--bind /tmp/opencode /tmp/opencode --chdir "$workdir")

exec bwrap "${args[@]}" -- "$real_bin" "$@"
