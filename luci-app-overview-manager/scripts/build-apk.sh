#!/bin/sh

set -eu

fail() {
  printf 'build-apk: %s\n' "$*" >&2
  exit 1
}

root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
. "$root/release.env"
sdk="${OPENWRT_SDK_DIR:-}"
[ -n "$sdk" ] || fail 'OPENWRT_SDK_DIR is required'
[ -d "$sdk" ] || fail "SDK directory not found: $sdk"
command -v rsync >/dev/null 2>&1 || fail 'rsync is required'

"$root/scripts/check-version-sync.sh"
sdk_package="$sdk/package/$PKG_NAME"
rm -rf "$sdk_package"
mkdir -p "$sdk_package"
rsync -a --delete \
  --exclude .git \
  --exclude build \
  --exclude dist \
  --exclude .DS_Store \
  "$root/" "$sdk_package/"

make -C "$sdk" defconfig
make -C "$sdk" "package/$PKG_NAME/clean" V=s

if [ -n "${OPENWRT_APK_SIGNING_KEY:-}" ] && [ -n "${OPENWRT_APK_PUBLIC_KEY:-}" ]; then
  make -C "$sdk" \
    BUILD_KEY_APK_SEC="$OPENWRT_APK_SIGNING_KEY" \
    BUILD_KEY_APK_PUB="$OPENWRT_APK_PUBLIC_KEY" \
    "package/$PKG_NAME/compile" V=s
else
  make -C "$sdk" "package/$PKG_NAME/compile" V=s
fi

package_path="$(find "$sdk/bin/packages" -type f \
  -name "${PKG_NAME}-${PKG_VERSION}.apk" -print -quit)"
[ -n "$package_path" ] || fail 'built APK was not found'
mkdir -p "$root/dist"
rm -f "$root/dist"/*.apk
cp "$package_path" "$root/dist/"
printf '%s\n' "$root/dist/${package_path##*/}"
