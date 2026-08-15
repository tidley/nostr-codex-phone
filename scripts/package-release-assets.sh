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
linux_bundle="build/linux/x64/release/bundle"
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
if [[ ! -x "$linux_bundle/nostr_codex_phone" ]]; then
  echo "Missing Linux desktop bundle: $linux_bundle" >&2
  echo "Run: flutter build linux --release" >&2
  exit 1
fi

rm -rf "$out"
mkdir -p "$out"

cp "$apk" "$out/code-call-v$version.apk"
cp "$worker" "$out/nostr-codex-worker-linux-x64"
chmod 755 "$out/nostr-codex-worker-linux-x64"
tar -C "$linux_bundle" -czf "$out/code-call-v$version-linux-x64.tar.gz" .

"${STRIP:-strip}" --strip-unneeded "$out/nostr-codex-worker-linux-x64"

sha256sum "$out"/* > "$out/SHA256SUMS"

worker_sha="$(sha256sum "$out/nostr-codex-worker-linux-x64" | cut -d' ' -f1)"
manifest="$out/worker-update.json"
cat >"$manifest" <<EOF
{
  "version": "$version",
  "artifact": "nostr-codex-worker-linux-x64",
  "sha256": "$worker_sha"
}
EOF

if [[ -n "${NOSTR_CODEX_UPDATE_SIGNING_KEY:-}" ]]; then
  command -v minisign >/dev/null 2>&1 || {
    echo "minisign is required to sign worker update metadata." >&2
    exit 1
  }
  minisign -Sm "$manifest" -s "$NOSTR_CODEX_UPDATE_SIGNING_KEY"
else
  echo "Worker update manifest is unsigned; OTA clients will reject it." >&2
fi

ls -lh "$out"
