#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Build a self-contained ucode toolchain on Linux so tests/run.sh can execute
# the ucode part locally (and in CI) without copying the checkout to an
# OpenWrt device. This is the only toolchain script on purpose: the target is
# Linux, the CI runner is Linux, and `sing-box check` accepts the Linux-only
# routing_mark only there - an off-target layer anywhere else would have to
# weaken the very configuration it exists to validate.
#
# Usage:
#   sh tests/toolchain/build-ucode-linux.sh [prefix] [build-dir]
#
# Defaults: prefix=~/.local/ucode-testbed  build-dir=/tmp/ucode-build
#
# After a successful build the script prints the PATH/shim setup that
# tests/run.sh expects. See tests/README.md for the runner contract.

set -eu

PREFIX="${1:-$HOME/.local/ucode-testbed}"
BUILD="${2:-/tmp/ucode-build}"

# The package Makefile targets sing-box 1.14; tests/ucode/test_generators.sh
# feeds the generated configs to `sing-box check`, so the version has to match.
SINGBOX_VERSION="1.14.0"

# ucode is pinned to the revision ImmortalWrt/OpenWrt snapshots shipped as
# package version 2026.01.16~85922056.  That ucode requires a terminating ';'
# after `export function ... }` and rejects object destructuring; upstream
# relaxed the trailing-';' rule afterwards (openwrt/openwrt@main and
# immortalwrt/immortalwrt@master now pin b885dd0f, whose own test suite uses
# the semicolon-free form).  Building ucode from the default branch therefore
# lets target-incompatible modules pass CI, which is exactly how the A/B
# refactor shipped five modules that no router could parse.
# tests/ucode/test_ucode_grammar.sh fails loudly if this pin is ever moved to
# a permissive revision, so the mismatch cannot come back unnoticed.
UCODE_REV="${UCODE_REV:-85922056ef7abeace3cca3ab28bc1ac2d88e31b1}"

# json-c (libubox) and libmd (digest module) come from apt. Their pkg-config
# files live under /usr/lib/<arch>-linux-gnu/pkgconfig, which pkg-config
# already searches; we just need to make sure the .pc files are installed.
if ! pkg-config --exists json-c; then
	echo "ERROR: json-c is required (apt install libjson-c-dev)" >&2
	exit 1
fi
if ! pkg-config --exists libmd; then
	echo "ERROR: libmd is required (apt install libmd-dev)" >&2
	exit 1
fi

mkdir -p "$PREFIX" "$PREFIX/bin" "$BUILD"
PREFIX="$(cd "$PREFIX" && pwd)"
BUILD="$(cd "$BUILD" && pwd)"

# BUILD_WITH_INSTALL_RPATH links against the final install location from the
# start, so `cmake --install` never has to rewrite the load commands. Linux
# uses RUNPATH and standard .so naming, so no install_name_tool step is needed
# here at all.
#
# CMAKE_INSTALL_RPATH is what BUILD_WITH_INSTALL_RPATH actually bakes in:
# without it the installed binaries get an empty RUNPATH, and the first
# `$PREFIX/bin/ucode` invocation in this script (and every later one, plus
# the test suite) dies with
#   libucode.so.0: cannot open shared object file
# $PREFIX/lib is not a default loader search path, so this has to be set.
CMAKE_COMMON="-DCMAKE_INSTALL_PREFIX=$PREFIX
	-DCMAKE_INSTALL_LIBDIR=lib
	-DCMAKE_BUILD_TYPE=Release
	-DCMAKE_BUILD_WITH_INSTALL_RPATH=ON
	-DCMAKE_INSTALL_RPATH=$PREFIX/lib
	-DCMAKE_PREFIX_PATH=$PREFIX"

# Optional second argument pins the checkout to a revision (branch, tag or
# full commit id).  Repositories without one keep tracking their default
# branch; only ucode is pinned, because upstream relaxed grammar rules the
# package still has to stay compatible with.
clone() {
	repo="$1"
	rev="${2:-}"
	dir="$BUILD/$(basename "$repo")"
	if [ -d "$dir/.git" ]; then
		git -C "$dir" fetch --depth 1 origin >/dev/null 2>&1 || true
	else
		git clone --depth 1 "https://github.com/$repo.git" "$dir"
	fi
	if [ -n "$rev" ]; then
		if ! git -C "$dir" fetch --depth 1 origin "$rev" >/dev/null 2>&1; then
			echo "ERROR: could not fetch $repo at $rev" >&2
			exit 1
		fi
		git -C "$dir" checkout -q --detach FETCH_HEAD
		# A build tree left over from another revision must not be reused.
		rm -rf "$dir/build"
	fi
	echo "$dir"
}

# The full luci tree is large and only one directory is needed; fetch it in
# partial/sparse mode so the toolchain build stays quick.
clone_sparse() {
	repo="$1"
	path="$2"
	dir="$BUILD/$(basename "$repo")"
	if [ ! -d "$dir/.git" ]; then
		git clone --depth 1 --filter=blob:none --sparse \
			"https://github.com/$repo.git" "$dir" >/dev/null
	fi
	git -C "$dir" sparse-checkout set "$path" >/dev/null
	echo "$dir"
}

build() {
	dir="$1"
	shift
	echo "==> building $(basename "$dir")"
	# shellcheck disable=SC2086
	cmake -S "$dir" -B "$dir/build" $CMAKE_COMMON "$@" >/dev/null
	cmake --build "$dir/build" -j"$(nproc)" >/dev/null
	cmake --install "$dir/build" >/dev/null
}

# libubox first: it provides ubox, blobmsg_json and the headers that both the
# uci and ubus modules (and ucode's own ubus/uci plugins) link against.
build "$(clone openwrt/libubox)" -DBUILD_LUA=OFF -DBUILD_EXAMPLES=OFF

# libuci: the cursor() implementation used by every generator and the RPC daemon.
build "$(clone openwrt/uci)" -DBUILD_LUA=OFF

# libubus: ubus.connect() is used by generate_client.uc and the RPC daemon.
build "$(clone openwrt/ubus)" -DBUILD_LUA=OFF

# ucode last, so its CMake detects all three libraries and enables the
# uci/ubus/uloop plugins. ffi / nl80211 / rtnl are off: not needed by the
# tests, and their headers are not in the OpenWrt tree on a default clone.
build "$(clone jow-/ucode "$UCODE_REV")" \
	-DUBUS_SUPPORT=ON -DUCI_SUPPORT=ON -DULOOP_SUPPORT=ON \
	-DFFI_SUPPORT=OFF -DNL80211_SUPPORT=OFF -DRTNL_SUPPORT=OFF \
	-DDEBUG_SUPPORT=ON -DZLIB_SUPPORT=ON

# liblucihttp: homeproxy-pro.uc, parse_uri.uc and the RPC daemon import
# luci.http for urldecode_params()/urlencode()/urldecode(). luci.http is a
# thin ucode wrapper around this C module, so it has to exist for the
# generators to even load. Built after ucode, whose headers it needs.
#
# Two flags are load-bearing, and omitting them is what left this step
# failing on CI (ucode/module.h not found, then a bare -lucode):
#   -I$PREFIX/include     upstream adds no include path for ucode, whose
#     module.h in turn pulls in json-c (from apt, so that part resolves).
#   -L$PREFIX/lib         upstream links `-lucode` by bare name without a
#     find_library() call, relying on libucode being in a default search
#     path. $PREFIX is not one.
LUCIHTTP_DIR="$(clone jow-/lucihttp)"
echo "==> building lucihttp"
cmake -S "$LUCIHTTP_DIR" -B "$LUCIHTTP_DIR/build" $CMAKE_COMMON \
	-DBUILD_LUA=OFF -DBUILD_TESTS=OFF \
	-DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
	-DCMAKE_SHARED_LINKER_FLAGS="-L$PREFIX/lib" \
	-DCMAKE_C_FLAGS="-Wno-error -I$PREFIX/include" >/dev/null
cmake --build "$LUCIHTTP_DIR/build" -j"$(nproc)" >/dev/null
cmake --install "$LUCIHTTP_DIR/build" >/dev/null

# The luci.* ucode modules themselves (http.uc, sys.uc, ...) are pure sources
# shipped by the luci-base package; OpenWrt installs them to
# /usr/share/ucode/luci. Stage the same layout inside the prefix so
# `import { urldecode_params } from 'luci.http'` resolves locally.
LUCI_DIR="$(clone_sparse openwrt/luci modules/luci-base/ucode)"
mkdir -p "$PREFIX/share/ucode/luci"
cp "$LUCI_DIR"/modules/luci-base/ucode/*.uc "$PREFIX/share/ucode/luci/"
cp -R "$LUCI_DIR"/modules/luci-base/ucode/controller "$PREFIX/share/ucode/luci/" 2>/dev/null || true
cp -R "$LUCI_DIR"/modules/luci-base/ucode/template "$PREFIX/share/ucode/luci/" 2>/dev/null || true

# sing-box is not built here, but the generator cases run `sing-box check` and
# the package targets sing-box >= 1.14, so an older binary reports unknown
# fields ("handshake_timeout", "certificate_provider") and fails the fixtures.
# Take the official release binary unless a matching one already exists.
sb_version() {
	if [ -x "$PREFIX/bin/sing-box" ]; then
		"$PREFIX/bin/sing-box" version 2>/dev/null |
			awk '/^sing-box version /{sub(/^sing-box version /,""); sub(/-.*/,""); print; exit}'
	fi
}
if [ "$(sb_version)" != "$SINGBOX_VERSION" ]; then
	echo "==> fetching sing-box $SINGBOX_VERSION"
	sb_tar="sing-box-$SINGBOX_VERSION-linux-amd64.tar.gz"
	sb_url="https://github.com/SagerNet/sing-box/releases/download/v$SINGBOX_VERSION/$sb_tar"
	if ! curl -fsSL "$sb_url" -o "$BUILD/$sb_tar" >/dev/null 2>&1; then
		echo "ERROR: could not download $sb_url" >&2
		exit 1
	fi
	tar xzf "$BUILD/$sb_tar" -C "$BUILD"
	cp "$BUILD/sing-box-$SINGBOX_VERSION-linux-amd64/sing-box" "$PREFIX/bin/sing-box"
	chmod +x "$PREFIX/bin/sing-box"
fi

echo
echo "==> verifying"
"$PREFIX/bin/ucode" -e 'printf("ucode %s\n", ARGV[0] ?? "ok");'
printf '  ucode rev  %s (pinned)\n' "$(git -C "$BUILD/ucode" rev-parse --short HEAD 2>/dev/null || echo unknown)"
printf '  sing-box   %s\n' "$("$PREFIX/bin/sing-box" version 2>/dev/null | head -1)"
FAILED=0

# utpl is what tests/ucode/test_firewall_template.sh renders firewall_post.ut
# with.  ucode installs it as a symlink to itself, so a toolchain without it
# would silently drop the firewall template check.
if [ -x "$PREFIX/bin/utpl" ]; then
	printf '  utpl       OK\n'
else
	printf '  utpl       MISSING\n'
	FAILED=1
fi

# The pinned ucode must keep enforcing the strict grammar the package targets;
# the canary turns a permissive upstream revision into a build failure instead
# of a silently green test run.  Requires utpl/ucode on PATH.
if PATH="$PREFIX/bin:$PATH" sh "$(dirname "$0")/../ucode/test_ucode_grammar.sh"; then
	printf '  grammar    strict (matches ImmortalWrt ucode)\n'
else
	printf '  grammar    MISMATCH - do not ship this toolchain\n'
	FAILED=1
fi

for mod in fs math uci ubus digest zlib struct resolv socket lucihttp luci.http luci.sys; do
	if "$PREFIX/bin/ucode" -e "import * as m from '$mod';" 2>/dev/null; then
		printf '  module %-10s OK\n' "$mod"
	else
		printf '  module %-10s MISSING\n' "$mod"
		FAILED=1
	fi
done

# Exercise the exact parser helper the share-link code depends on, so a
# broken lucihttp binding is detected here rather than mid-refactor. The
# expected values mirror upstream semantics: '+' decodes to a space inside a
# value and a repeated key keeps the last occurrence.
if ! "$PREFIX/bin/ucode" -e '
	import { urldecode_params } from "luci.http";
	let p = urldecode_params("a=1&b=x+y&b=2");
	(p.a == "1" && p.b == "2") || exit(1);
' 2>/dev/null; then
	echo "  luci.http urldecode_params  MISMATCH"
	FAILED=1
fi

echo
if [ "$FAILED" -eq 0 ]; then
	echo "==> done"
else
	echo "==> done WITH PROBLEMS (see MISSING/MISMATCH above)" >&2
	exit 1
fi
echo "prefix: $PREFIX"
echo
echo "Add the toolchain to PATH (needed by tests/run.sh):"
echo "  export PATH=\"$PREFIX/bin:\$PATH\""
echo "The prefix also carries the matching sing-box, so it must come before any"
echo "other sing-box in PATH (e.g. /usr/local/bin)."

exit 0
