#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# ucode grammar canary.
#
# The package has to parse on the ucode that ImmortalWrt/OpenWrt snapshots
# ship (2026.01.16~85922056 at the time of writing), and that ucode is
# STRICTER than current upstream HEAD:
#
#   * `export function name() { ... }` must be terminated by ';'
#     (upstream relaxed this in b885dd0f, whose own test suite uses the
#      semicolon-free form; openwrt/openwrt@main now pins that revision)
#   * object destructuring (`const { a } = x;`) is rejected
#
# A toolchain built from ucode's default branch therefore accepts code that
# no router can parse, and the whole suite stays green while the package is
# dead on arrival.  That is exactly how the A/B refactor shipped five modules
# (config/loader.uc, subscription/{filter,decoder,fetcher,repository}.uc) that
# failed to compile on a target, plus an update_subscriptions.uc that used
# destructuring.
#
# This check pins the *dialect* rather than a revision: it asserts that the
# ucode under test still rejects those two constructs, so a permissive
# toolchain fails here instead of hiding a target regression.  It also asserts
# that the constructs the package legitimately relies on still compile, so
# pinning ucode to something too old fails here too.
#
# Set HP_ALLOW_PERMISSIVE_UCODE=1 to demote the "must be rejected" failures to
# warnings when deliberately probing a newer ucode.
#
# Usage: sh tests/ucode/test_ucode_grammar.sh

WORK="$(mktemp -d "${TMPDIR:-/tmp}/hp-ucode-grammar.XXXXXX")" || exit 1
trap 'rm -rf "$WORK"' EXIT INT TERM

if ! command -v ucode > "/dev/null" 2>&1; then
	echo "NOT RUN: ucode is not on PATH"
	exit 2
fi

FAILED=0
ALLOW_PERMISSIVE="${HP_ALLOW_PERMISSIVE_UCODE:-0}"

# compile <name> <source...> : write a module and try to load it.  `export`
# is only legal in a module, so the probe must go through `import` rather than
# `ucode -c` on the file directly.
compiles() {
	name="$1"
	shift
	file="$WORK/$name.uc"
	printf '%s\n' "$*" > "$file"
	ucode -e "import * as m from \"$file\";" >/dev/null 2>&1
}

# --- constructs the package relies on: these MUST compile -----------------

accept() {
	name="$1"
	src="$2"
	if compiles "$name" "$src"; then
		echo "PASS: $name compiles"
	else
		echo "FAIL: $name does not compile (toolchain too old or broken)"
		FAILED=1
	fi
}

# --- constructs the target rejects: these MUST fail ----------------------

reject() {
	name="$1"
	src="$2"
	if compiles "$name" "$src"; then
		if [ "$ALLOW_PERMISSIVE" = "1" ]; then
			echo "WARN: $name compiles (permissive ucode allowed by HP_ALLOW_PERMISSIVE_UCODE=1)"
		else
			echo "FAIL: $name compiles, but the target ucode rejects it"
			echo "      the toolchain is more permissive than ImmortalWrt/OpenWrt 2026.01.16"
			echo "      (pin tests/toolchain/build-ucode-*.sh UCODE_REV to a strict revision)"
			FAILED=1
		fi
	else
		echo "PASS: $name rejected by ucode (matches the target)"
	fi
}

accept exported_function_strict 'export function f() { return 1; };'
accept plain_function 'function g() { return 1; }'
accept const_export 'export const c = 1;'
accept computed_key_object "export const t = { ['a']: 1 };"
accept optional_chaining_and_nullish 'export function g(o) { return o?.a ?? 1; };'
accept object_spread 'export function h() { return { ...{ a: 1 } }; };'
accept template_literal 'export function i(v) { return `x${v}`; };'

reject exported_function_without_semicolon 'export function f() { return 1; }'
reject object_destructuring 'export function h(o) { const { a } = o; return a; };'
reject array_destructuring 'export function i(a) { const [x] = a; return x; };'

exit $FAILED
