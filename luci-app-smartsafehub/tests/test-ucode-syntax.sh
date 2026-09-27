#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
UCODE_ROOT="$ROOT_DIR/root/usr/share/rpcd/ucode"
CI_WORKFLOW="$ROOT_DIR/.github/workflows/ci.yml"

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

[ -d "$UCODE_ROOT" ] || fail 'rpcd ucode directory is missing'
[ -f "$CI_WORKFLOW" ] || fail 'GitHub Actions CI workflow is missing'

grep -Fq 'UCODE_REF: 8592205' "$CI_WORKFLOW" || \
	fail 'CI must pin the OpenWrt 25.12 ucode compiler revision'
grep -Fq "SMARTSAFEHUB_REQUIRE_UCODE: '1'" "$CI_WORKFLOW" || \
	fail 'CI must require real ucode compilation instead of silently skipping it'
grep -Fq 'git clone https://github.com/jow-/ucode.git "$RUNNER_TEMP/ucode"' "$CI_WORKFLOW" || \
	fail 'CI must build the pinned ucode compiler before running backend tests'

if ! command -v ucode >/dev/null 2>&1; then
	if [ "${SMARTSAFEHUB_REQUIRE_UCODE:-0}" = '1' ]; then
		fail 'ucode compiler is required but was not found in PATH'
	fi

	printf '%s\n' 'PASS: ucode compiler is unavailable locally; CI still requires full rpcd ucode compilation'
	exit 0
fi

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/smartsafehub-ucode.XXXXXX")"
AGGREGATE_MODULE="$UCODE_ROOT/.smartsafehub-syntax-all.$$.uc"
trap 'rm -rf "$TMP_ROOT"; rm -f "$AGGREGATE_MODULE"' EXIT HUP INT TERM

# Host-built ucode does not include OpenWrt-only dynamic modules. Minimal source
# stubs let the compiler resolve those imports while still compiling all project
# source and relative imports with the real target-language parser.
cat > "$TMP_ROOT/ubus.uc" <<'STUB'
export function connect() {
	return null;
};
STUB

cat > "$TMP_ROOT/uci.uc" <<'STUB'
export function cursor() {
	return null;
};
STUB

cat > "$TMP_ROOT/fs.uc" <<'STUB'
export function __smartsafehub_fs_stub() {
	return null;
};
STUB

compile_ucode() {
	source_file="$1"
	output_file="$2"
	log_file="$3"

	if ! ucode -L "$TMP_ROOT" -L "$UCODE_ROOT" -c -o "$output_file" "$source_file" >"$log_file" 2>&1; then
		cat "$log_file" >&2
		fail "ucode compilation failed: ${source_file#$ROOT_DIR/}"
	fi

	[ -s "$output_file" ] || fail "ucode compiler produced no bytecode: ${source_file#$ROOT_DIR/}"
}

entry_count=0
find "$UCODE_ROOT" -maxdepth 1 -type f -name '*.uc' -print | sort |
while IFS= read -r entry; do
	entry_count=$((entry_count + 1))
	compile_ucode \
		"$entry" \
		"$TMP_ROOT/entry-$entry_count.ucb" \
		"$TMP_ROOT/entry-$entry_count.log"
done

# Compile every reusable module as a module, including modules that may not yet
# be reachable from an rpcd entrypoint. This prevents dormant syntax errors from
# entering the tree and becoming production failures when a later import is added.
module_count=0
: > "$AGGREGATE_MODULE"
find "$UCODE_ROOT" -mindepth 2 -type f -name '*.uc' -print | sort |
while IFS= read -r module; do
	module_count=$((module_count + 1))
	relative="${module#$UCODE_ROOT/}"
	printf "import * as module_%d from './%s';\n" "$module_count" "$relative" >> "$AGGREGATE_MODULE"
done
printf '%s\n' 'return true;' >> "$AGGREGATE_MODULE"

compile_ucode \
	"$AGGREGATE_MODULE" \
	"$TMP_ROOT/all-modules.ucb" \
	"$TMP_ROOT/all-modules.log"

# Guard against a compiler/configuration mismatch by proving the target compiler
# rejects the exact class of export-termination error that previously prevented
# rpcd objects from registering.
cat > "$TMP_ROOT/invalid-export.uc" <<'INVALID'
export function broken_export() {
	return true;
}
INVALID
cat > "$TMP_ROOT/invalid-entry.uc" <<'INVALID_ENTRY'
import { broken_export } from './invalid-export.uc';
return broken_export();
INVALID_ENTRY

if ucode -L "$TMP_ROOT" -c -o "$TMP_ROOT/invalid.ucb" "$TMP_ROOT/invalid-entry.uc" >/dev/null 2>&1; then
	fail 'ucode compiler unexpectedly accepted an export function without the required semicolon'
fi

printf '%s\n' 'PASS: all rpcd ucode entrypoints and modules compile with the OpenWrt-compatible compiler'
