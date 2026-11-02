#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
UCODE_ROOT="$ROOT_DIR/root/usr/share/rpcd/ucode"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

[ -f "$UCODE_ROOT/smartsafehub/apps-storage.uc" ] || fail 'Apps storage ucode module not found'

if ! command -v ucode >/dev/null 2>&1; then
    [ "${SMARTSAFEHUB_REQUIRE_UCODE:-0}" != '1' ] || fail 'Apps storage runtime requires ucode in PATH'
    printf '%s\n' 'PASS: Apps storage module exists (runtime requires CI ucode)'
    exit 0
fi

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/smartsafehub-apps-storage.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM

# Run the existing assertions against the production module, never a copy.
# The temporary runner keeps tests/ limited to ShellSpec-discovered *.sh tests.
ln -s "$UCODE_ROOT/smartsafehub" "$TMP_ROOT/smartsafehub"
cat > "$TMP_ROOT/runner.uc" <<'EOF_UCODE'
'use strict';
import { from_system_root, from_statvfs } from './smartsafehub/apps-storage.uc';
function check(ok, message) {
	if (!ok) {
		warn(`FAIL: ${message}\n`);
		exit(1);
	}
};
let s = from_system_root({ total: 65536, avail: 40960 });
check(s?.mount == '/' && s?.totalBytes == 67108864 && s?.availableBytes == 41943040,
      'procd root stats must convert KiB to bytes');
check(from_system_root({ total: 500, avail: 501 }) == null, 'invalid root counters');
check(from_system_root({ total: '65536', avail: '40960' }) == null, 'reject string counters');
check(from_system_root({ total: 9007199254740991, avail: 1 }) == null, 'reject integer overflow');
check(from_system_root(null) == null, 'missing procd statistics must be optional');
check(from_system_root({ total: 42, avail: 0 })?.availableBytes == 0, 'allow a full filesystem');
let t = from_statvfs({ frsize: 4096, blocks: 20000, bavail: 13000 }, '/overlay');
check(t?.totalBytes == 81920000 && t?.availableBytes == 53248000, 'statvfs basic units');
check(from_statvfs({ frsize: 0, bsize: 4096, blocks: 20000, bavail: 0 }, '/')?.availableBytes == 0,
      'fall back to bsize if frsize is zero');
check(from_statvfs({ frsize: 4096, blocks: 20000, bavail: 20001 }, '/') == null,
      'reject invalid available blocks');
check(from_statvfs({ frsize: 4096, blocks: 20000, bavail: 1 }, '/tmp') == null,
      'must never use tmpfs instead of APK storage');
check(from_statvfs(null, '/overlay') == null, 'missing statvfs stats must be optional');
EOF_UCODE

ucode -L "$TMP_ROOT" -L "$UCODE_ROOT" "$TMP_ROOT/runner.uc" || \
    fail 'Apps storage ucode runtime contract failed'

printf '%s\n' 'PASS: Apps storage procd and statvfs conversions'
