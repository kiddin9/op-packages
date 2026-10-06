#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${1:-$ROOT_DIR/dist}"

PKG_NAME="minigate"
PKG_VERSION="2026.9.18-2"
PKG_ARCH="all"
PKG_FILE="${PKG_NAME}_${PKG_VERSION}_${PKG_ARCH}.ipk"
DEPS="libc, luci-base, nginx-ssl, nginx-mod-stream, openssl-util, wget, curl, jsonfilter, coreutils-stat, nftables"

WORK_DIR="$(mktemp -d)"

CONTROL_DIR="$WORK_DIR/control"
DATA_DIR="$WORK_DIR/data"
PKG_DIR="$WORK_DIR/pkg"

mkdir -p "$CONTROL_DIR" "$DATA_DIR" "$PKG_DIR" "$OUT_DIR"

mkdir -p \
	"$DATA_DIR/usr/lib/lua/luci/controller" \
	"$DATA_DIR/usr/lib/lua/luci/model/cbi/minigate" \
	"$DATA_DIR/usr/lib/lua/luci/view/minigate" \
	"$DATA_DIR/usr/lib/minigate" \
	"$DATA_DIR/etc/config" \
	"$DATA_DIR/etc/init.d" \
	"$DATA_DIR/etc/minigate/acme" \
	"$DATA_DIR/etc/minigate/certs" \
	"$DATA_DIR/etc/minigate/nginx/sites" \
	"$DATA_DIR/etc/minigate/nginx/streams" \
	"$DATA_DIR/etc/minigate/login-guard"

install -m 0644 "$ROOT_DIR/luasrc/controller/minigate.lua" "$DATA_DIR/usr/lib/lua/luci/controller/minigate.lua"
install -m 0644 "$ROOT_DIR"/luasrc/model/cbi/minigate/*.lua "$DATA_DIR/usr/lib/lua/luci/model/cbi/minigate/"
install -m 0644 "$ROOT_DIR"/luasrc/view/minigate/*.htm "$DATA_DIR/usr/lib/lua/luci/view/minigate/"
install -m 0755 "$ROOT_DIR"/root/usr/lib/minigate/*.sh "$DATA_DIR/usr/lib/minigate/"
install -m 0644 "$ROOT_DIR/root/etc/config/minigate" "$DATA_DIR/etc/config/minigate"
install -m 0755 "$ROOT_DIR/root/etc/init.d/minigate" "$DATA_DIR/etc/init.d/minigate"

if [ -f "$ROOT_DIR/po/zh-cn/minigate.po" ] && command -v po2lmo >/dev/null 2>&1; then
	mkdir -p "$DATA_DIR/usr/lib/lua/luci/i18n"
	po2lmo "$ROOT_DIR/po/zh-cn/minigate.po" "$DATA_DIR/usr/lib/lua/luci/i18n/minigate.zh-cn.lmo"
fi

cat > "$CONTROL_DIR/control" <<EOF
Package: $PKG_NAME
Version: $PKG_VERSION
Provides: luci-app-minigate
Conflicts: luci-app-minigate
Replaces: luci-app-minigate
Depends: $DEPS
Source: feeds/luci/applications/$PKG_NAME
SourceName: $PKG_NAME
Section: luci
Architecture: $PKG_ARCH
Installed-Size: $(du -sk "$DATA_DIR" | awk '{print $1}')
Maintainer: MiniGate
License: MIT
Description: LuCI - MiniGate (DDNS + ACME + Reverse Proxy + Login Guard)
 Lightweight gateway management for OpenWrt: Cloudflare DDNS, Let's Encrypt SSL certificates,
 Nginx reverse proxy, and SSH/LuCI brute-force ban (Login Guard) with LuCI web interface.
EOF

cat > "$CONTROL_DIR/conffiles" <<'EOF'
/etc/config/minigate
EOF

cat > "$CONTROL_DIR/postinst" <<'EOF'
#!/bin/sh
[ -n "${IPKG_INSTROOT}" ] || {
	chmod +x /etc/init.d/minigate
	chmod +x /usr/lib/minigate/*.sh
	/etc/init.d/minigate enable
	echo "MiniGate installed. Configure at: LuCI -> Services -> MiniGate"
}
EOF

cat > "$CONTROL_DIR/prerm" <<'EOF'
#!/bin/sh
[ -n "${IPKG_INSTROOT}" ] || {
	/etc/init.d/minigate stop
	/etc/init.d/minigate disable
}
EOF

chmod 0755 "$CONTROL_DIR/postinst" "$CONTROL_DIR/prerm"

printf '2.0\n' > "$PKG_DIR/debian-binary"

tar_create_root() {
	out_file="$1"
	shift

	if tar --version 2>/dev/null | grep -qi 'bsdtar'; then
		COPYFILE_DISABLE=1 tar --format ustar --no-xattrs --no-mac-metadata \
			--uid 0 --gid 0 --uname root --gname root -czf "$out_file" "$@"
	elif tar --help 2>/dev/null | grep -q -- '--owner'; then
		tar --format=ustar --owner=0 --group=0 --numeric-owner -czf "$out_file" "$@"
	else
		tar -czf "$out_file" "$@"
	fi
}

(
	cd "$CONTROL_DIR"
	tar_create_root "$PKG_DIR/control.tar.gz" control conffiles postinst prerm
)

(
	cd "$DATA_DIR"
	tar_create_root "$PKG_DIR/data.tar.gz" .
)

(
	cd "$PKG_DIR"
	# OpenWrt opkg on newer 24.10 builds expects this outer archive to be tar.gz,
	# not the Debian-style ar container accepted by some older opkg versions. Use
	# ustar to avoid pax extended headers that opkg reports as typeflag 0x78.
	tar_create_root "$OUT_DIR/$PKG_FILE" debian-binary control.tar.gz data.tar.gz
)

echo "$OUT_DIR/$PKG_FILE"
