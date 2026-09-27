#!/bin/sh
set -eu
fail() { printf 'build-apk: %s\n' "$*" >&2; exit 1; }
root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
. "$root/release.env"
. "$root/apk-feed.env"
sdk="${OPENWRT_SDK_DIR:-}"
[ -d "$sdk" ] || fail 'OPENWRT_SDK_DIR must name an extracted SDK'
apk_tool="$sdk/staging_dir/host/bin/apk"
[ -x "$apk_tool" ] || fail 'SDK apk tool is unavailable'
"$root/scripts/check-version-sync.sh"
work="$(mktemp -d)"
cleanup() {
  if [ -d "$work" ]; then
    chown -R "$(id -u):$(id -g)" "$work" 2>/dev/null ||
      sudo -n chown -R "$(id -u):$(id -g)" "$work" 2>/dev/null || true
    rm -rf "$work"
  fi
}
trap cleanup EXIT HUP INT TERM
"$root/scripts/stage-package.sh" "$work/full"
mkdir -p "$work/payload"
cp -R "$work/full/usr" "$work/full/www" "$work/payload/"
if ! chown -R 0:0 "$work/payload" 2>/dev/null; then
  command -v sudo >/dev/null 2>&1 || fail 'root-owned APK staging requires chown or sudo'
  sudo -n chown -R 0:0 "$work/payload" || fail 'could not normalize APK ownership'
fi
mkdir -p "$root/dist"
artifact="$root/dist/$PKG_NAME-$PKG_VERSION.apk"
"$apk_tool" mkpkg \
  --info "name:$PKG_NAME" \
  --info "version:$PKG_VERSION" \
  --info 'description:Active Wi-Fi access point QR codes for LuCI Status Overview' \
  --info "arch:$OPENWRT_APK_ARCH" \
  --info 'license:MIT' \
  --info "origin:$PKG_NAME" \
  --info 'maintainer:nikitid' \
  --info 'depends:libc luci-base luci-lib-uqr' \
  --script "post-install:$work/full/CONTROL/postinst" \
  --script "post-upgrade:$work/full/CONTROL/postinst" \
  --script "pre-deinstall:$work/full/CONTROL/prerm" \
  --files "$work/payload" \
  --output "$artifact"
"$apk_tool" adbdump --format json "$artifact" >"$work/package.json"
python3 - "$work/package.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    package = json.load(source)
if package.get("info", {}).get("depends") != ["libc", "luci-base", "luci-lib-uqr"]:
    raise SystemExit("unexpected APK dependency set")
for path in package.get("paths", []):
    entries = [path] + path.get("files", [])
    for entry in entries:
        acl = entry.get("acl", {})
        if acl.get("user") != "root" or acl.get("group") != "root":
            raise SystemExit("APK contains a non-root-owned path")
if any(path.get("name") == "CONTROL" for path in package.get("paths", [])):
    raise SystemExit("IPK control directory leaked into APK payload")
scripts = package.get("scripts", {})
if set(scripts) != {"post-install", "post-upgrade", "pre-deinstall"}:
    raise SystemExit("unexpected APK lifecycle scripts")
PY
printf '%s\n' "$artifact"
