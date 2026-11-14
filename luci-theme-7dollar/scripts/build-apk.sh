#!/bin/sh
# Build dist/luci-theme-7dollar-<version>.apk for OpenWrt 25.x (apk-tools v3).
# Needs apk-tools v3 (`apk mkpkg`, set APK=/path/to/apk.static) and runs as root so files are
# owned by root; .github/workflows/apk.yml does both.
set -eu
cd "$(dirname "$0")/.."

NAME=luci-theme-7dollar
VER=$(sed -n 's/^PKG_VERSION:=//p' Makefile)-r$(sed -n 's/^PKG_RELEASE:=//p' Makefile)
OUT=dist/$NAME-$VER.apk
# Stamp files with the last commit that touched the package, so rebuilding unchanged sources
# gives a byte-identical apk (CI then has nothing to commit).
export SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(git -c safe.directory="$PWD" log -1 --format=%ct -- Makefile htdocs ucode root scripts/stage.sh scripts/build-apk.sh)}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

D=$TMP/data S=$TMP/scripts
sh scripts/stage.sh "$D"
mkdir -p "$D/lib/apk/packages" "$S"
( cd "$D" && find . \( -type f -o -type l \) | sed 's/^\.//' | sort ) > "$TMP/list"
mv "$TMP/list" "$D/lib/apk/packages/$NAME.list"
echo /etc/config/7dollar > "$D/lib/apk/packages/$NAME.conffiles"
echo "/etc/config/7dollar $(sha256sum "$D/etc/config/7dollar" | cut -d' ' -f1)" > "$D/lib/apk/packages/$NAME.conffiles_static"

# Same maintainer scripts OpenWrt's package-pack.mk generates for apk packages.
cat > "$S/post-install" <<SH
#!/bin/sh
[ "\${IPKG_NO_SCRIPT}" = "1" ] && exit 0
[ -s "\${IPKG_INSTROOT}/lib/functions.sh" ] || exit 0
. \${IPKG_INSTROOT}/lib/functions.sh
export root="\${IPKG_INSTROOT}"
export pkgname="$NAME"
default_postinst
[ -n "\${IPKG_INSTROOT}" ] || {
	rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache/
	/etc/init.d/rpcd reload >/dev/null 2>&1
}
exit 0
SH
{ echo '#!/bin/sh'; echo 'export PKG_UPGRADE=1'; sed 1d "$S/post-install"; } > "$S/post-upgrade"
cat > "$S/pre-deinstall" <<SH
#!/bin/sh
[ -s "\${IPKG_INSTROOT}/lib/functions.sh" ] || exit 0
. \${IPKG_INSTROOT}/lib/functions.sh
export root="\${IPKG_INSTROOT}"
export pkgname="$NAME"
default_prerm
SH
cat > "$S/post-deinstall" <<'SH'
#!/bin/sh
[ -n "${IPKG_INSTROOT}" ] || {
	uci -q delete luci.themes.7Dollar
	[ "$(uci -q get luci.main.mediaurlbase)" = "/luci-static/7dollar" ] && \
		uci -q set luci.main.mediaurlbase=/luci-static/bootstrap
	uci commit luci
	rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache/
}
exit 0
SH
chmod 755 "$S"/*
find "$D" "$S" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +

mkdir -p dist
rm -f dist/$NAME-*.apk
${APK:-apk} mkpkg \
	--info "name:$NAME" \
	--info "version:$VER" \
	--info "description:7Dollar, an elegant, lightweight LuCI theme" \
	--info "arch:noarch" \
	--info "license:Apache-2.0" \
	--info "origin:$NAME" \
	--info "url:https://github.com/itsmaiGe/luci-theme-7dollar" \
	--info "maintainer:itsmaiGe" \
	--info "depends:libc luci-base" \
	--script "post-install:$S/post-install" \
	--script "post-upgrade:$S/post-upgrade" \
	--script "pre-deinstall:$S/pre-deinstall" \
	--script "post-deinstall:$S/post-deinstall" \
	--files "$D" \
	--output "$OUT"
basename "$OUT" > dist/latest-apk.txt
echo "$OUT ($(wc -c < "$OUT" | tr -d ' ') bytes)"
