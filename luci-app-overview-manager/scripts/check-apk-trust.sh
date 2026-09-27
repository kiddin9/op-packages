#!/bin/sh

set -eu

fail() {
  printf 'check-apk-trust: %s\n' "$*" >&2
  exit 1
}

root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
. "$root/apk-feed.env"
public_key="$root/$OPENWRT_APK_KEY_FILE"

[ -r "$public_key" ] || fail "public key not found: $OPENWRT_APK_KEY_FILE"
actual="$(sha256sum "$public_key" | awk '{ print $1 }')"
[ "$actual" = "$OPENWRT_APK_TRUST_SHA256" ] ||
  fail "public key checksum mismatch: $actual"
openssl pkey -pubin -in "$public_key" -noout >/dev/null 2>&1 ||
  fail 'release public key is not a valid PEM public key'

tracked_files() {
  find "$root" -path "$root/.git" -prune -o \
    -path "$root/build" -prune -o -path "$root/dist" -prune -o \
    -type f -print
}

# Keep this in sync with the secret patterns in .gitignore. The previous
# anchored form missed names such as release-private.pem.
if tracked_files |
    grep -Ei '\.key$|private[^/]*\.(pem|key)$|signing[^/]*\.(pem|key)$|/signing/' \
    >/dev/null; then
  fail 'private signing material is present in the source tree'
fi

# A private key under an unexpected name still has recognisable contents. The
# scan runs in a subshell, so it only reports and leaves failing to the caller.
key_material="$(tracked_files |
  grep -Ei '\.(pem|key|crt)$' |
  while IFS= read -r candidate; do
    if grep -q 'PRIVATE KEY' "$candidate"; then
      printf '%s\n' "${candidate#"$root"/}"
    fi
  done)"
[ -z "$key_material" ] ||
  fail "private key material found in: $(printf '%s' "$key_material" | tr '\n' ' ')"

# Contract with the shared feed (see openwrt-feed/docs/MEMBER_INTEGRATION.md):
# this repository signs
# and publishes only its own package. It must not host a feed URL, ship a trust
# bootstrap of its own or assemble an index.
[ "${OPENWRT_FEED_REPOSITORY:-}" = Nikitid/openwrt-feed ] ||
  fail 'OPENWRT_FEED_REPOSITORY must name the shared feed'

[ ! -e "$root/scripts/install-openwrt25.sh" ] ||
  fail 'the shared installer replaced scripts/install-openwrt25.sh; remove it'

if grep -rlE 'raw\.githubusercontent\.com/Nikitid/[A-Za-z0-9._-]+/apk-feed' \
    "$root/scripts" "$root/docs" "$root/.github" "$root"/*.md "$root"/*.env \
    2>/dev/null | grep -q .; then
  fail 'a retired per-application feed URL is still referenced'
fi

# Contract rule: every package transaction names the packages it touches, so a
# release never upgrades the whole router.
blanket="$(tracked_files |
  grep -E '\.(sh|md|yml|env)$' |
  xargs awk '
    /(apk|opkg)[ \t]+upgrade/ {
      rest = $0
      sub(/.*(apk|opkg)[ \t]+upgrade/, "", rest)
      gsub(/[ \t]*--[a-zA-Z-]+/, "", rest)
      gsub(/[ \t]/, "", rest)
      if (rest == "" || rest ~ /^([;&|#]|\|\||&&)/)
        printf "%s:%d\n", FILENAME, FNR
    }
  ' 2>/dev/null)"
[ -z "$blanket" ] ||
  fail "package upgrade without an explicit package name: $(
    printf '%s' "$blanket" | tr '\n' ' ')"

printf 'APK trust configuration OK\n'
