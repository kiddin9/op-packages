#!/bin/sh

set -eu

REPO="itv3/homeproxy"
PKG_NAME="homeproxy-custom"
ASSET="homeproxy-custom_all.apk"
TMP_APK="/tmp/$ASSET"
URL="https://github.com/$REPO/releases/latest/download/$ASSET"
KEY_NAME="homeproxy-custom.pem"
KEY_URL="https://github.com/$REPO/releases/latest/download/$KEY_NAME"
KEY_FINGERPRINT="sha256:88cc3293f56077364a252a059c259bcf028f647e9e9f4cf5a30dca678c2e5b47"
REPO_LIST="/etc/apk/repositories.d/homeproxy-custom.list"
REPO_INDEX_URL="https://github.com/$REPO/releases/latest/download/Packages.adb"

trap 'rm -f "$TMP_APK"' EXIT

echo "HomeProxy Custom installer"

if [ ! -x /usr/bin/apk ]; then
	echo "error: this installer currently supports apk-based OpenWrt/ImmortalWrt only"
	exit 1
fi

if [ ! -x /usr/bin/wget ] && [ ! -x /bin/wget ]; then
	echo "error: wget is required"
	exit 1
fi

mkdir -p /etc/apk/keys /etc/apk/repositories.d

echo "install repository key"
wget -O "/etc/apk/keys/$KEY_NAME" "$KEY_URL" || exit 1

if [ -n "$KEY_FINGERPRINT" ]; then
	echo "verify public key fingerprint"
	actual_fp=$(sha256sum "/etc/apk/keys/$KEY_NAME" | awk '{print $1}')
	expected_fp="${KEY_FINGERPRINT#sha256:}"
	if [ "$actual_fp" != "$expected_fp" ]; then
		echo "error: public key fingerprint mismatch" >&2
		echo "expected: $expected_fp" >&2
		echo "actual: $actual_fp" >&2
		rm -f "/etc/apk/keys/$KEY_NAME"
		exit 1
	fi
	echo "public key fingerprint verified"
fi

echo "configure repository"
printf '%s\n' "$REPO_INDEX_URL" > "$REPO_LIST"

echo "remove standalone translation package if installed"
apk del luci-i18n-homeproxy-zh-cn 2>/dev/null || true

install_direct_apk() {
	echo "download: $URL"
	wget -O "$TMP_APK" "$URL" || return 1

	echo "verify APK signature"
	if apk verify --keys-dir /etc/apk/keys "$TMP_APK" 2>&1; then
		echo "APK signature verified"
	else
		echo "error: APK signature verification failed" >&2
		rm -f "$TMP_APK"
		return 1
	fi

	echo "install package"
	apk add --upgrade "$TMP_APK"
}

echo "update package index"
if apk update && apk add --upgrade "$PKG_NAME"; then
	echo "installed from repository"
else
	echo "warning: repository install failed, falling back to direct APK install" >&2
	install_direct_apk
fi

echo "clean .apk-new files"
find /etc/homeproxy /etc/config -name "*.apk-new" -exec rm -f {} \; 2>/dev/null || true

echo "restart services"
rm -f /tmp/luci-indexcache.* 2>/dev/null || true
rm -rf /tmp/luci-modulecache/ 2>/dev/null || true
/etc/init.d/rpcd restart 2>/dev/null || true
/etc/init.d/uhttpd restart 2>/dev/null || true
/etc/init.d/homeproxy restart 2>/dev/null || true

echo "installed:"
apk list -I | grep -E '^(homeproxy-custom|luci-app-homeproxy)' || true
echo "success"
