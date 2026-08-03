#!/usr/bin/env bash
set -euo pipefail

exec cargo run --manifest-path rust/Cargo.toml --bin fips-call-harness -- "$@"
