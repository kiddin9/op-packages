#!/bin/sh
set -eu
fail() { printf 'build-apk-release: %s\n' "$*" >&2; exit 1; }
root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
. "$root/release.env"
. "$root/apk-feed.env"
sdk="${OPENWRT_SDK_DIR:-}"
secret="${OPENWRT_APK_SIGNING_KEY:-}"
public="$root/$OPENWRT_APK_KEY_FILE"
[ -d "$sdk" ] || fail 'OPENWRT_SDK_DIR must name an extracted SDK'
[ -r "$secret" ] || fail 'OPENWRT_APK_SIGNING_KEY is not readable'
[ -r "$public" ] || fail 'shared public key is not readable'
"$root/scripts/check-apk-trust.sh"
verify_dir="$(mktemp -d)"
trap 'rm -rf "$verify_dir"' EXIT HUP INT TERM
openssl ec -in "$secret" -pubout -out "$verify_dir/public.pem" >/dev/null 2>&1 ||
  fail 'invalid EC signing key'
cmp -s "$verify_dir/public.pem" "$public" || fail 'signing key does not match shared public key'
OPENWRT_APK_SIGNING_KEY="$secret" OPENWRT_APK_PUBLIC_KEY="$public" \
  "$root/scripts/build-apk.sh"
apk_tool="$sdk/staging_dir/host/bin/apk"
package="$root/dist/$PKG_NAME-$PKG_VERSION.apk"
[ -x "$apk_tool" ] || fail 'SDK apk tool is unavailable'
[ -r "$package" ] || fail 'built APK is unavailable'
"$apk_tool" --allow-untrusted adbsign --sign-key "$secret" "$package"
"$apk_tool" --keys-dir "$root/keys" verify "$package"
mkdir -p "$root/dist/apk"
cp "$package" "$root/dist/apk/"
(cd "$root/dist/apk" && sha256sum "$PKG_NAME-$PKG_VERSION.apk" >SHA256SUMS.apk)
