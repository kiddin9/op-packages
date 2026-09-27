#!/bin/sh
# shellcheck shell=sh

ss_case_ucode() (
	set -eu
	MODULE_DIR="$SS_SPEC_ROOT/files/usr/share/rpcd/ucode/safeshield"
	ENTRY="$SS_SPEC_ROOT/files/usr/share/rpcd/ucode/safeshield.uc"
	STATUS_STORE="$SS_SPEC_ROOT/files/usr/lib/safeshield/status-store.uc"
	UCODE_BIN="${UCODE:-ucode}"
	if ! command -v "$UCODE_BIN" >/dev/null 2>&1; then
		[ "${REQUIRE_UCODE:-0}" != '1' ]
		return 0
	fi
	TMPDIR="$(ss_spec_tmpdir)"
	trap 'rm -rf "$TMPDIR"' EXIT HUP INT TERM
	compile_ucode() {
		file="$1"
		output="$TMPDIR/$(basename -- "$file").ucb"
		"$UCODE_BIN" -c -o "$output" "$file" >/dev/null
	}
	compile_ucode "$ENTRY"
	compile_ucode "$STATUS_STORE"
	for file in "$MODULE_DIR"/*.uc; do
		compile_ucode "$file"
	done
	run_ucode_test() {
		name="$1"
		mock_dir="$SS_SPEC_ROOT/tests/ucode/mocks/$name"
		test_file="$SS_SPEC_ROOT/tests/ucode/test_$name.uc"
		test_tmp="$TMPDIR/$name"
		test_modules="$TMPDIR/modules/$name"
		mkdir -p "$test_tmp" "$test_modules"
		cp "$MODULE_DIR/$name.uc" "$test_modules/$name.uc"
		cp "$mock_dir"/*.uc "$test_modules/"
		"$UCODE_BIN" -L "$test_modules" -D "TEST_TMP=\"$test_tmp\"" "$test_file" >/dev/null
	}
	for name in core config license refresh rules statistics status runtime; do
		run_ucode_test "$name"
	done

	status_file="$TMPDIR/status-store.json"
	printf '%s\n' 'not-json' >"$status_file"
	out="$("$UCODE_BIN" "$STATUS_STORE" "$status_file" dump)"
	printf '%s\n' "$out" | grep -F '"data":{}' >/dev/null
	printf '%s\n' "$out" | grep -F '"warnings":[]' >/dev/null
	printf '%s\n' "$out" | grep -F '"errors":[]' >/dev/null

	out="$("$UCODE_BIN" "$STATUS_STORE" "$status_file" set stage running)"
	printf '%s\n' "$out" >"$status_file"
	printf '%s\n' "$out" | grep -F '"stage":"running"' >/dev/null
	out="$("$UCODE_BIN" "$STATUS_STORE" "$status_file" add_warning dnsmasq_warning)"
	printf '%s\n' "$out" >"$status_file"
	printf '%s\n' "$out" | grep -F '"code":"dnsmasq_warning"' >/dev/null
	out="$("$UCODE_BIN" "$STATUS_STORE" "$status_file" add_error artifact_download_failed)"
	printf '%s\n' "$out" >"$status_file"
	printf '%s\n' "$out" | grep -F '"code":"artifact_download_failed"' >/dev/null
	out="$("$UCODE_BIN" "$STATUS_STORE" "$status_file" clear_messages)"
	printf '%s\n' "$out" | grep -F '"warnings":[]' >/dev/null
	printf '%s\n' "$out" | grep -F '"errors":[]' >/dev/null
	out="$("$UCODE_BIN" "$STATUS_STORE" "$status_file" reset)"
	printf '%s\n' "$out" | grep -F '"data":{}' >/dev/null
	if "$UCODE_BIN" "$STATUS_STORE" "$status_file" set >/dev/null 2>&1; then
		return 1
	fi
	if "$UCODE_BIN" "$STATUS_STORE" "$status_file" unknown >/dev/null 2>&1; then
		return 1
	fi
)
