#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
UCODE_ROOT="$ROOT_DIR/root/usr/share/rpcd/ucode"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT INT TERM

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

[ -d "$UCODE_ROOT" ] || fail 'rpcd ucode directory is missing'

find "$UCODE_ROOT" -type f -name '*.uc' -print | sort > "$TMP"
[ -s "$TMP" ] || fail 'no rpcd ucode modules found'

while IFS= read -r source; do
	sed -n "s/.*from[[:space:]]*'\([^']*\)'.*/\1/p" "$source" |
	while IFS= read -r target; do
		case "$target" in
			./*|../*)
				resolved="$(dirname "$source")/$target"
				[ -f "$resolved" ] || \
					fail "missing relative ucode import in ${source#$ROOT_DIR/}: $target"
				;;
		esac
	done
done < "$TMP"

echo 'PASS: all relative rpcd ucode imports resolve to existing files'
