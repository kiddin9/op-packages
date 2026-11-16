#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
#
# Build luci-app-nginx-console on the router itself: no OpenWrt SDK, no CI
# round-trip.  Useful while the package is still being built up.
#
#   Usage: bash scripts/build-local.sh [router]
#
# Why the router: building an apk needs apk-tools v3 with `apk mkpkg`, and the
# apk-tools that OpenWrt ships does not have that command.  A static apk-tools
# from Alpine is downloaded once and kept at /tmp/apk.static on the router.
#
# The package is architecture independent, so nothing gets compiled: everything
# under root/ and htdocs/ is the input.  See .github/build-pkg.sh for the
# version that CI uses.

set -o errexit
set -o pipefail
set -o nounset

ROUTER="${1:-root@192.168.1.140}"
ALPINE_MIRROR="${ALPINE_MIRROR:-https://mirrors.tuna.tsinghua.edu.cn/alpine/edge/main/x86_64}"
# The apk-tools-static version is resolved from the mirror's APKINDEX unless it
# is given explicitly: Alpine drops old point releases from the mirror, so a
# hard coded version breaks as soon as the branch moves on.
APK_TOOLS_STATIC_VERSION="${APK_TOOLS_STATIC_VERSION:-}"

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
NAME=luci-app-nginx-console
OUT_DIR="${REPO_DIR}/dist"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

say() { printf '\033[1m==> %s\033[0m\n' "$*"; }
fail() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

VERSION="$(sed -n 's/^PKG_VERSION:=//p' "$REPO_DIR/Makefile" | head -n1 | tr -d '[:space:]')"
RELEASE="$(sed -n 's/^PKG_RELEASE:=//p' "$REPO_DIR/Makefile" | head -n1 | tr -d '[:space:]')"
[ -n "$VERSION" ] && [ -n "$RELEASE" ] || fail "cannot read PKG_VERSION / PKG_RELEASE from Makefile"
PKGVER="${VERSION}-r${RELEASE}"

say "Staging file tree for ${NAME} ${PKGVER}"

TREE="${STAGE}/${NAME}"
mkdir -p "$TREE"

[ -d "$REPO_DIR/root" ] || fail "missing root/ directory"
[ -d "$REPO_DIR/htdocs" ] || fail "missing htdocs/ directory"

cp -a "$REPO_DIR/root/." "$TREE/"
mkdir -p "$TREE/www"
cp -a "$REPO_DIR/htdocs/." "$TREE/www/"

# macOS sprinkles these around; they must never reach the package.
find "$TREE" -name '._*' -delete
find "$TREE" -name '.DS_Store' -delete

find "$TREE" -type d -exec chmod 0755 {} +
find "$TREE" -type f -exec chmod 0644 {} +
chmod 0755 "$TREE/usr/libexec/nginx-console" || fail "usr/libexec/nginx-console is missing"
chmod 0755 "$TREE/usr/libexec/nginx-console-write" || fail "usr/libexec/nginx-console-write is missing"

( cd "$STAGE" && COPYFILE_DISABLE=1 tar czf "${STAGE}/tree.tgz" "$NAME" )

say "Checking the router"

ssh "$ROUTER" 'command -v apk >/dev/null' || fail "no apk on the router"

if ! ssh "$ROUTER" '[ -x /tmp/apk.static ]'; then
	if [ -z "$APK_TOOLS_STATIC_VERSION" ]; then
		say "Resolving the newest apk-tools-static in ${ALPINE_MIRROR}"

		APKINDEX="$(mktemp)"
		curl -sL --max-time 120 "${ALPINE_MIRROR}/APKINDEX.tar.gz" |
			tar -xzO APKINDEX > "$APKINDEX" ||
			fail "cannot read APKINDEX from ${ALPINE_MIRROR}"

		APK_TOOLS_STATIC_VERSION="$(awk '
			/^P:apk-tools-static$/ { hit = 1; next }
			hit && /^V:/ { print substr($0, 3); exit }
			hit && /^$/ { hit = 0 }
		' "$APKINDEX")"

		[ -n "$APK_TOOLS_STATIC_VERSION" ] ||
			fail "apk-tools-static is not in ${ALPINE_MIRROR}"
	fi

	say "Fetching apk-tools-static ${APK_TOOLS_STATIC_VERSION} onto the router"

	ssh "$ROUTER" "sh -s" <<REMOTE
set -e
cd /tmp
curl -fsL --max-time 120 -o /tmp/apk-tools-static.apk \
	'${ALPINE_MIRROR}/apk-tools-static-${APK_TOOLS_STATIC_VERSION}.apk'
mkdir -p /tmp/apkstatic
tar -xzf /tmp/apk-tools-static.apk -C /tmp/apkstatic sbin/apk.static
mv /tmp/apkstatic/sbin/apk.static /tmp/apk.static
chmod 0755 /tmp/apk.static
rm -rf /tmp/apkstatic /tmp/apk-tools-static.apk
REMOTE
fi

ssh "$ROUTER" '/tmp/apk.static mkpkg 2>&1 | grep -q "required info field" ' ||
	fail "the apk.static on the router cannot build packages"

say "Uploading and building on the router"

scp -q "${STAGE}/tree.tgz" "${ROUTER}:/tmp/${NAME}-tree.tgz"

ssh "$ROUTER" "sh -s" <<REMOTE
set -e
PKG=/tmp/pkgbuild/${NAME}
rm -rf /tmp/pkgbuild /tmp/pkgbuild-dist
mkdir -p "\$PKG" /tmp/pkgbuild-dist
tar xzf /tmp/${NAME}-tree.tgz -C /tmp/pkgbuild

chown -R root:root "\$PKG"
find "\$PKG" -type d -exec chmod 0755 {} +
find "\$PKG" -type f -exec chmod 0644 {} +
chmod 0755 "\$PKG/usr/libexec/nginx-console"
chmod 0755 "\$PKG/usr/libexec/nginx-console-write"

mkdir -p "\$PKG/lib/apk/packages"
cd "\$PKG"
find . -type f | grep -v '^\./lib/apk/packages/' | sed 's|^\./|/|' | sort \
	> /tmp/${NAME}.list
mv /tmp/${NAME}.list "\$PKG/lib/apk/packages/${NAME}.list"

# The rate limits are a conffile: a hand edited rate must survive an upgrade.
printf '%s\n' '/etc/nginx/conf.d/nginx-console-limits.conf' \
	> "\$PKG/lib/apk/packages/${NAME}.conffiles"

cat > /tmp/${NAME}-post-install <<'INNER'
#!/bin/sh
[ "\${IPKG_NO_SCRIPT}" = "1" ] && exit 0
[ -s \${IPKG_INSTROOT}/lib/functions.sh ] || exit 0
. \${IPKG_INSTROOT}/lib/functions.sh
export root="\${IPKG_INSTROOT}"
export pkgname="${NAME}"
default_postinst \$0 \$@
[ -n "\${IPKG_INSTROOT}" ] || {
	rm -f /tmp/luci-indexcache.*
	rm -rf /tmp/luci-modulecache/
	killall -HUP rpcd 2>/dev/null
	exit 0
}
INNER
chmod 0755 /tmp/${NAME}-post-install
cp /tmp/${NAME}-post-install /tmp/${NAME}-post-upgrade

/tmp/apk.static mkpkg \
	--info "name:${NAME}" \
	--info "version:${PKGVER}" \
	--info "description:LuCI console for the nginx UCI configuration" \
	--info "arch:noarch" \
	--info "license:Apache-2.0" \
	--info "origin:https://github.com/szwjp/${NAME}" \
	--info "url:https://github.com/szwjp/${NAME}" \
	--info "maintainer:szwjp <szwjp@users.noreply.github.com>" \
	--info "depends:luci-base rpcd rpcd-mod-file jsonfilter nginx" \
	--script "post-install:/tmp/${NAME}-post-install" \
	--script "post-upgrade:/tmp/${NAME}-post-upgrade" \
	--files "\$PKG" \
	--output "/tmp/pkgbuild-dist/${NAME}-${PKGVER}.apk"

rm -rf /tmp/pkgbuild /tmp/${NAME}-tree.tgz
rm -f /tmp/${NAME}-post-install /tmp/${NAME}-post-upgrade
REMOTE

mkdir -p "$OUT_DIR"
scp -q "${ROUTER}:/tmp/pkgbuild-dist/${NAME}-${PKGVER}.apk" "$OUT_DIR/"
ssh "$ROUTER" 'rm -rf /tmp/pkgbuild-dist'

say "Built ${OUT_DIR}/${NAME}-${PKGVER}.apk"
ls -la "${OUT_DIR}/${NAME}-${PKGVER}.apk"
echo
echo "Install or upgrade on the router with:"
echo "  scp dist/${NAME}-${PKGVER}.apk ${ROUTER}:/tmp/"
echo "  ssh ${ROUTER} 'apk add --allow-untrusted --force-overwrite /tmp/${NAME}-${PKGVER}.apk'"
