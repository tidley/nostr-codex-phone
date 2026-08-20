#!/usr/bin/env bash
set -euo pipefail

root="$(dirname "$(dirname "$(readlink -f "$0")")")"
version="${1:-0.3.47}"
architecture="amd64"
bundle="$root/build/linux/x64/release/bundle"
output="$root/build/nostr-codex-phone_${version}_${architecture}.deb"
stage="$(mktemp -d "$root/build/nostr-codex-phone-deb.XXXXXX")"

if [[ ! -x "$bundle/nostr_codex_phone" ]]; then
  printf 'Build the Linux release bundle first: flutter build linux --release\n' >&2
  exit 1
fi

trap 'rm -rf "$stage"' EXIT
install -d "$stage/DEBIAN" "$stage/opt/nostr-codex-phone" \
  "$stage/usr/bin" "$stage/usr/share/applications" \
  "$stage/usr/share/icons/hicolor/256x256/apps"
cp -a "$bundle/." "$stage/opt/nostr-codex-phone/"
install -m 0644 "$root/assets/branding/ribbet-mark.png" \
  "$stage/usr/share/icons/hicolor/256x256/apps/nostr-codex-phone.png"

printf '%s\n' \
  'Package: nostr-codex-phone' \
  "Version: $version" \
  "Architecture: $architecture" \
  'Maintainer: Nostr Codex <support@nostr-codex.app>' \
  'Depends: libc6, libgtk-3-0, libsecret-1-0, libstdc++6' \
  'Section: net' \
  'Priority: optional' \
  'Description: Encrypted OpenCode collaboration client' \
  ' Nostr Codex connects desktop clients to OpenCode workers through encrypted Nostr messages.' \
  > "$stage/DEBIAN/control"

printf '%s\n' \
  '#!/bin/sh' \
  'exec /opt/nostr-codex-phone/nostr_codex_phone "$@"' \
  > "$stage/usr/bin/nostr-codex-phone"
chmod 0755 "$stage/usr/bin/nostr-codex-phone"

printf '%s\n' \
  '[Desktop Entry]' \
  'Type=Application' \
  'Name=Nostr Codex Phone' \
  'Comment=Encrypted OpenCode collaboration client' \
  'Exec=nostr-codex-phone' \
  'Icon=nostr-codex-phone' \
  'Categories=Network;Development;' \
  'Terminal=false' \
  > "$stage/usr/share/applications/nostr-codex-phone.desktop"

dpkg-deb --build --root-owner-group "$stage" "$output"
printf '%s\n' "$output"
