#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Automatically syntax-check test/spec scripts and shipped router shell files.
set -eu
ROOT_DIR="${1:-$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)}"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
for directory in tests spec root/usr/lib root/usr/libexec root/etc/init.d root/etc/rc.button; do
    [ -d "$ROOT_DIR/$directory" ] || fail "missing shell source directory: $directory"
done
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT HUP INT TERM
{
    find "$ROOT_DIR/tests" "$ROOT_DIR/spec" -type f -name '*.sh' -print
    find "$ROOT_DIR/root/usr/lib" -type f -name '*.sh' -print
    find "$ROOT_DIR/root/usr/libexec" "$ROOT_DIR/root/etc/init.d" \
        "$ROOT_DIR/root/etc/rc.button" -type f -print
} | LC_ALL=C sort -u > "$TMP"
[ -s "$TMP" ] || fail 'no shell sources found'
while IFS= read -r script; do
    [ -f "$script" ] || fail "missing shell source: $script"
    sh -n "$script" || fail "invalid shell syntax: ${script#"$ROOT_DIR"/}"
done < "$TMP"
printf 'PASS: auto-discovered shell source syntax\n'
