#!/usr/bin/env bash
set -euo pipefail

export CODEX_WORKDIR="${CODEX_WORKDIR:-$PWD}"
export AGENT_WORKDIR="${AGENT_WORKDIR:-$CODEX_WORKDIR}"

state_dir="$CODEX_WORKDIR/.nostr-codex"
mkdir -p "$state_dir"

worker="${NOSTR_CODEX_WORKER:-$state_dir/nostr-codex-worker-linux-x64}"
fallback_worker="$state_dir/nostr-codex-worker"
legacy_worker="$CODEX_WORKDIR/nostr-codex-worker-linux-x64"
legacy_fallback_worker="$CODEX_WORKDIR/nostr-codex-worker"
worker_url="${NOSTR_CODEX_WORKER_URL:-https://github.com/tidley/nostr-codex-phone/releases/latest/download/nostr-codex-worker-linux-x64}"

if [[ ! -x "$worker" && -x "$fallback_worker" ]]; then
  worker="$fallback_worker"
fi
if [[ ! -x "$worker" && -x "$legacy_worker" ]]; then
  worker="$legacy_worker"
fi
if [[ ! -x "$worker" && -x "$legacy_fallback_worker" ]]; then
  worker="$legacy_fallback_worker"
fi

if [[ ! -x "$worker" ]]; then
  if ! command -v curl >/dev/null 2>&1; then
    echo "curl is required to download the Nostr Codex worker." >&2
    exit 1
  fi
  echo "Downloading Nostr Codex worker to $worker" >&2
  curl -fsSL --retry 3 --connect-timeout 10 -o "$worker" "$worker_url"
  chmod +x "$worker"
fi

codex_args="${CODEX_ARGS:-}"
transcribe_args="${TRANSCRIBE_ARGS:-}"

if [[ -z "$codex_args" ]]; then
  codex_args="--ask-for-approval never --sandbox danger-full-access -c model_reasoning_effort=medium exec --skip-git-repo-check"
fi

if [[ -z "$transcribe_args" ]]; then
  transcribe_args="-m /home/tom/code/phone/models/ggml-base.en.bin -f {audio} -otxt -of {output_dir}/transcript -nt"
fi

export RUST_LOG="${RUST_LOG:-info,nostr_codex_server=debug,nostr_sdk=info,nostr=info}"
export NOSTR_RELAYS="${NOSTR_RELAYS:-wss://relay.damus.io,wss://nos.lol,wss://nostr.mom}"
export NOSTR_CODEX_ENV_FILE="${NOSTR_CODEX_ENV_FILE:-$state_dir/.env.server}"
export CODEX_MEMORY_DB="${CODEX_MEMORY_DB:-$state_dir/memory.sqlite3}"
export AGENT_BACKEND="${AGENT_BACKEND:-opencode}"
export OPENCODE_URL="${OPENCODE_URL:-http://127.0.0.1:4096}"
export OPENCODE_BIN="${OPENCODE_BIN:-opencode}"
export OPENCODE_AGENT="${OPENCODE_AGENT:-build}"
export CODEX_BIN="${CODEX_BIN:-codex}"
export CODEX_ARGS="$codex_args"
export TRANSCRIBE_BIN="${TRANSCRIBE_BIN:-/home/tom/.local/bin/whisper-cpp}"
export TRANSCRIBE_ARGS="$transcribe_args"

exec "$worker"
