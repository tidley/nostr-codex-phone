#!/usr/bin/env bash
set -euo pipefail

version="${1:-}"
if [[ -z "$version" ]]; then
  version="$(awk '/^version:/ {print $2; exit}' pubspec.yaml)"
  version="${version%%+*}"
fi
version="${version#v}"

apk="build/app/outputs/flutter-apk/app-release.apk"
worker="rust/target/release/nostr-codex-server"
out="build/release-assets/v$version"

if [[ ! -f "$apk" ]]; then
  echo "Missing APK: $apk" >&2
  echo "Run: flutter build apk --release" >&2
  exit 1
fi
if [[ ! -x "$worker" ]]; then
  echo "Missing worker binary: $worker" >&2
  echo "Run: cargo build --release --manifest-path rust/Cargo.toml --bin nostr-codex-server" >&2
  exit 1
fi

rm -rf "$out"
mkdir -p "$out"

cp "$apk" "$out/code-call-v$version.apk"
cp "$worker" "$out/nostr-codex-worker-linux-x64"
chmod 755 "$out/nostr-codex-worker-linux-x64"

"${STRIP:-strip}" --strip-unneeded "$out/nostr-codex-worker-linux-x64"

sha256sum "$out"/* > "$out/SHA256SUMS"
ls -lh "$out"
