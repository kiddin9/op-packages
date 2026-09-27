#!/bin/sh
# shellcheck shell=busybox
# SPDX-License-Identifier: GPL-2.0-only
# Builds jsonfilter for the test suites on a development host or CI runner.
# It comes from jsonpath, linked against a static libubox, both at the
# commits the ImmortalWrt image uses. Needs git, cmake, a C compiler and the
# json-c headers (Ubuntu: cmake libjson-c-dev). The binary lands in
# <dir>/bin/jsonfilter.

set -eu

LIBUBOX_REF=7dd127841e82eb1cfb61185da37dde7b9bd9ba6d
JSONPATH_REF=b9034210bd331749673416c6bf389cccd4e23610

[ $# -eq 1 ] || { echo "usage: build-jsonfilter.sh <dir>" >&2; exit 2; }
mkdir -p "$1"
out=$(cd "$1" && pwd)
src="$out/src"

fetch() { # $1 project, $2 commit
	[ -d "$src/$1" ] || git clone -q "https://git.openwrt.org/project/$1.git" "$src/$1"
	git -C "$src/$1" checkout -q "$2"
}
fetch libubox "$LIBUBOX_REF"
fetch jsonpath "$JSONPATH_REF"

cmake -S "$src/libubox" -B "$src/libubox/build" -DBUILD_LUA=OFF -DBUILD_EXAMPLES=OFF \
	> /dev/null
cmake --build "$src/libubox/build" --target ubox-static > /dev/null
mkdir -p "$out/include/libubox" "$out/lib" "$out/bin"
cp "$src"/libubox/*.h "$out/include/libubox/"
cp "$src/libubox/build/libubox.a" "$out/lib/"

# jsonpath builds in its source tree, its parser generator uses relative paths.
cmake -S "$src/jsonpath" -B "$src/jsonpath" -DCMAKE_INCLUDE_PATH="$out/include" \
	-DCMAKE_EXE_LINKER_FLAGS="-L$out/lib" > /dev/null
cmake --build "$src/jsonpath" > /dev/null
cp "$src/jsonpath/jsonpath" "$out/bin/jsonfilter"
echo "$out/bin/jsonfilter"
