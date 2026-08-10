#!/usr/bin/env bash
set -euo pipefail

workdir="$(pwd -P)"
read_root="${AGENT_READ_ROOT:-$(dirname "$workdir")}"
read_root="$(realpath "$read_root")"
real_bin="${OPENCODE_REAL_BIN:-${OPENCODE_BIN_REAL:-opencode}}"

case "$workdir/" in
  "$read_root/"*) ;;
  *)
    printf 'Agent working directory must be inside read root: %s\n' "$read_root" >&2
    exit 1
    ;;
esac

# The code tree is read-only by default. Rebinding the selected working
# directory grants the agent the minimum write access needed to make changes.
args=(
  --ro-bind / /
  --bind "$workdir" "$workdir"
  --dev-bind /dev /dev
  --proc /proc
  --bind /tmp /tmp
  --chdir "$workdir"
)

# OpenCode stores sessions and credentials outside the source tree.
for path in "$HOME/.config" "$HOME/.cache" "$HOME/.local"; do
  [[ -d "$path" ]] && args+=(--bind "$path" "$path")
done

exec bwrap "${args[@]}" -- "$real_bin" "$@"
