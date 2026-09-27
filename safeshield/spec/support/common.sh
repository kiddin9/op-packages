#!/bin/sh
# shellcheck shell=sh

SS_SPEC_ROOT="${SS_SPEC_ROOT:-$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)}"

ss_spec_tmpdir() {
	mktemp -d
}

ss_spec_assert_eq() {
	[ "$1" = "$2" ]
}

ss_spec_assert_ne() {
	[ "$1" != "$2" ]
}

ss_spec_assert_file_contains() {
	grep -Fq -- "$2" "$1"
}

ss_spec_assert_file_not_contains() {
	! grep -Fq -- "$2" "$1"
}

ss_spec_assert_file_line() {
	grep -Fxq -- "$2" "$1"
}

ss_spec_assert_exists() {
	[ -e "$1" ]
}

ss_spec_assert_not_exists() {
	[ ! -e "$1" ]
}

ss_spec_assert_nonempty() {
	[ -s "$1" ]
}
