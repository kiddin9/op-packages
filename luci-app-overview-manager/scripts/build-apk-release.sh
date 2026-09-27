#!/bin/sh

set -eu

fail() {
  printf 'build-apk-release: %s\n' "$*" >&2
  exit 1
}

root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
. "$root/release.env"
. "$root/apk-feed.env"

sdk="${OPENWRT_SDK_DIR:-}"
signing_key="${OPENWRT_APK_SIGNING_KEY:-}"
public_key="$root/$OPENWRT_APK_KEY_FILE"
output="$root/dist/apk"

[ -n "$sdk" ] || fail 'OPENWRT_SDK_DIR is required'
[ -d "$sdk" ] || fail "SDK directory not found: $sdk"
[ -n "$signing_key" ] || fail 'OPENWRT_APK_SIGNING_KEY is required'
[ -r "$signing_key" ] || fail "signing key not readable: $signing_key"
[ -r "$public_key" ] || fail "public key not found: $public_key"

case "$(basename "$sdk")" in
  "${OPENWRT_APK_SDK_ARCHIVE%.tar.zst}") ;;
  *) fail "unexpected SDK directory: $(basename "$sdk")" ;;
esac

for command in make openssl rsync sha256sum; do
  command -v "$command" >/dev/null 2>&1 ||
    fail "required command is missing: $command"
done

"$root/scripts/check-apk-trust.sh"
tmp="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp"
}
trap cleanup EXIT HUP INT TERM

openssl ec -in "$signing_key" -pubout \
  -out "$tmp/derived-public.pem" >/dev/null 2>&1 ||
  fail 'invalid EC signing key'
cmp -s "$tmp/derived-public.pem" "$public_key" ||
  fail 'signing key does not match the shared public release key'

OPENWRT_APK_PUBLIC_KEY="$public_key" \
OPENWRT_APK_SIGNING_KEY="$signing_key" \
  "$root/scripts/build-apk.sh"

apk_tool="$sdk/staging_dir/host/bin/apk"
[ -x "$apk_tool" ] || fail "SDK apk tool not found: $apk_tool"
package="$root/dist/${PKG_NAME}-${PKG_VERSION}.apk"
[ -r "$package" ] || fail "built APK was not found: $package"

"$apk_tool" --allow-untrusted adbsign --sign-key "$signing_key" "$package"
"$apk_tool" --keys-dir "$root/keys" verify "$package"

# Only this package is published. Nikitid/openwrt-feed collects the released
# APK and builds the shared signed index, so no public key, bootstrap script or
# index is shipped from here.
rm -rf "$output"
mkdir -p "$output"
cp "$package" "$output/"
(
  cd "$output"
  sha256sum "${PKG_NAME}-${PKG_VERSION}.apk" >SHA256SUMS.apk
  sha256sum -c SHA256SUMS.apk
)

printf 'Signed APK built in %s\n' "$output"
