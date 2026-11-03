#!/bin/sh
set -eu
root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
. "$root/apk-feed.env"
actual="$(sha256sum "$root/$OPENWRT_APK_KEY_FILE" | awk '{print $1}')"
[ "$actual" = "$OPENWRT_APK_TRUST_SHA256" ] || {
  printf 'shared APK public key checksum mismatch\n' >&2
  exit 1
}
if grep -R -E '(apk|opkg)[[:space:]]+upgrade([[:space:]]*$|[[:space:]]*(&&|;))' \
    "$root/scripts" "$root/README.md" >/dev/null 2>&1; then
  printf 'unscoped package upgrade found\n' >&2
  exit 1
fi
